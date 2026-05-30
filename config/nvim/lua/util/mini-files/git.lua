-- Git status integration for mini.files
-- Based on https://gist.github.com/bassamsdata/eec0a3065152226581f8d4244cce9051

local api = vim.api
local ns = api.nvim_create_namespace("mini_files_git")

-- Define our own highlight groups using Dracula palette — no dependency on lazy-loaded plugins
api.nvim_set_hl(0, "MiniFilesGitAdd", { fg = "#50fa7b" })      -- green
api.nvim_set_hl(0, "MiniFilesGitChange", { fg = "#8BE9FD" })   -- cyan
api.nvim_set_hl(0, "MiniFilesGitDelete", { fg = "#ff5555" })   -- red

local gitStatusCache = {}
local pendingFetches = {} -- maps cwd -> list of buf_ids waiting for the fetch
local cacheTimeout = 10 -- seconds

local statusMap = {
  [" M"] = { symbol = "•", hlGroup = "MiniFilesGitChange" },
  ["M "] = { symbol = "✹", hlGroup = "MiniFilesGitChange" },
  ["MM"] = { symbol = "≠", hlGroup = "MiniFilesGitChange" },
  ["A "] = { symbol = "+", hlGroup = "MiniFilesGitAdd" },
  ["AA"] = { symbol = "≈", hlGroup = "MiniFilesGitAdd" },
  [" D"] = { symbol = "-", hlGroup = "MiniFilesGitDelete" },
  ["D "] = { symbol = "-", hlGroup = "MiniFilesGitDelete" },
  ["AM"] = { symbol = "⊕", hlGroup = "MiniFilesGitChange" },
  ["AD"] = { symbol = "-•", hlGroup = "MiniFilesGitChange" },
  ["R "] = { symbol = "→", hlGroup = "MiniFilesGitChange" },
  ["RM"] = { symbol = "→", hlGroup = "MiniFilesGitChange" },
  ["RD"] = { symbol = "→", hlGroup = "MiniFilesGitChange" },
  ["U "] = { symbol = "‖", hlGroup = "MiniFilesGitChange" },
  ["UU"] = { symbol = "⇄", hlGroup = "MiniFilesGitAdd" },
  ["UA"] = { symbol = "⊕", hlGroup = "MiniFilesGitAdd" },
  ["??"] = { symbol = "?", hlGroup = "MiniFilesGitAdd" },
  ["!!"] = { symbol = "!", hlGroup = "MiniFilesGitChange" },
}

-- Priority for bubbling: higher wins when a directory has children with different statuses
local statusPriority = {
  ["UU"] = 6, ["UA"] = 6, ["U "] = 6,
  ["MM"] = 5, ["M "] = 5, [" M"] = 5,
  ["A "] = 4, ["AA"] = 4, ["AM"] = 4, ["AD"] = 4,
  ["R "] = 3, ["RM"] = 3, ["RD"] = 3,
  ["??"] = 2,
  [" D"] = 1, ["D "] = 1,
}

local function fetchGitStatus(cwd, callback)
  vim.system(
    { "git", "status", "--ignored", "--porcelain" },
    { text = true, cwd = cwd },
    function(content)
      -- Always call back (nil on failure) so pendingFetches gets cleared
      callback(content.code == 0 and content.stdout or nil)
    end
  )
end

--- Strip C-style quoting that git uses for paths with spaces or non-ASCII.
--- Handles all escapes from git's quote.c: \a \b \f \n \r \t \v \\ \" and \NNN octal.
local function unquote(path)
  if path:sub(1, 1) ~= '"' or path:sub(-1) ~= '"' then return path end
  local escape_map = { a = "\a", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", v = "\v", ["\\"] = "\\", ['"'] = '"' }
  local inner = path:sub(2, -2)
  local result, i = {}, 1
  while i <= #inner do
    if inner:sub(i, i) == "\\" and i < #inner then
      local c = inner:sub(i + 1, i + 1)
      if escape_map[c] then
        result[#result + 1] = escape_map[c]; i = i + 2
      elseif c:match("[0-3]") then
        -- Git uses exactly 3 octal digits (\0XX-\3XX)
        local oct = inner:match("^([0-3][0-7][0-7])", i + 1)
        if oct then
          result[#result + 1] = string.char(tonumber(oct, 8))
          i = i + 1 + #oct
        else
          result[#result + 1] = "\\"; result[#result + 1] = c; i = i + 2
        end
      else result[#result + 1] = "\\"; result[#result + 1] = c; i = i + 2 end
    else
      result[#result + 1] = inner:sub(i, i); i = i + 1
    end
  end
  return table.concat(result)
end

local function updateMiniWithGit(buf_id, gitStatus)
  vim.schedule(function()
    if not api.nvim_buf_is_valid(buf_id) then return end
    api.nvim_buf_clear_namespace(buf_id, ns, 0, -1)

    local MiniFiles = require("mini.files")
    local nlines = api.nvim_buf_line_count(buf_id)

    -- Derive git root from the first entry's path (not vim.fs.root on the
    -- scratch buffer, which falls back to cwd and can be wrong)
    local first_entry = MiniFiles.get_fs_entry(buf_id, 1)
    if not first_entry then return end
    local cwd = vim.fs.root(first_entry.path, ".git")
    if not cwd then return end
    local escapedcwd = vim.pesc(vim.fs.normalize(cwd))
    local lines = api.nvim_buf_get_lines(buf_id, 0, nlines, false)
    local statusMapByPath = gitStatus.statusMap or {}
    local untrackedDirs = gitStatus.untrackedDirs or {}

    for i = 1, nlines do
      local entry = MiniFiles.get_fs_entry(buf_id, i)
      if not entry then break end

      local relativePath = entry.path:gsub("^" .. escapedcwd .. "/", "")
      local status = statusMapByPath[relativePath]

      -- Inherit status from untracked ancestor directories (git only
      -- reports "?? dir/" without listing individual children). Do not use
      -- bubbled parent statuses here, or one untracked child will mark every
      -- sibling in the directory as untracked.
      if not status then
        local parent = relativePath
        while true do
          parent = parent:match("^(.+)/[^/]+$")
          if not parent then break end
          if untrackedDirs[parent] then
            status = "??"
            break
          end
        end
      end

      if status then
        local info = statusMap[status] or { symbol = "✗", hlGroup = "NonText" }
        api.nvim_buf_set_extmark(buf_id, ns, i - 1, 0, {
          sign_text = info.symbol,
          sign_hl_group = info.hlGroup,
          priority = 2,
        })

        -- Find where the filename starts in the raw line using mini.files'
        -- internal format: /%04d/icon /name — avoids matching short names
        -- inside the concealed path index prefix
        local line = lines[i]
        local _, nameStart = line:find("^/%d+/.-/")
        if nameStart then
          -- Highlight from name start to end of line (handles sanitized names
          -- where display length may differ from #entry.name)
          api.nvim_buf_set_extmark(buf_id, ns, i - 1, nameStart, {
            end_col = #line,
            hl_group = info.hlGroup,
          })
        end
      end
    end
  end)
end

local function parseGitStatus(content)
  local gitStatusMap = {}
  local untrackedDirs = {}
  for line in content:gmatch("[^\r\n]+") do
    local status, filePath = string.match(line, "^(..) (.*)")
    if not status or not filePath then goto continue end

    -- Handle renames/copies: "R  old -> new" (only for R/C statuses).
    -- Unquote AFTER splitting so each path is unquoted independently.
    if status:sub(1, 1) == "R" or status:sub(1, 1) == "C" then
      local dest = filePath:match("^.+ -> (.+)$")
      filePath = dest and unquote(dest) or unquote(filePath)
    else
      filePath = unquote(filePath)
    end

    local isUntrackedDir = status == "??" and filePath:sub(-1) == "/"

    -- Strip trailing slash from untracked/ignored directories
    filePath = filePath:gsub("/$", "")
    if isUntrackedDir then
      untrackedDirs[filePath] = true
    end

    local parts = {}
    for part in filePath:gmatch("[^/]+") do
      parts[#parts + 1] = part
    end

    -- Mark the file itself
    gitStatusMap[filePath] = status

    -- Bubble status up to parent directories (but not for ignored files).
    -- Use priority to ensure the most important status wins.
    if status ~= "!!" then
      local priority = statusPriority[status] or 0
      for i = 1, #parts - 1 do
        local currentKey = table.concat(parts, "/", 1, i)
        local existing = gitStatusMap[currentKey]
        if not existing or (statusPriority[existing] or 0) < priority then
          gitStatusMap[currentKey] = status
        end
      end
    end
    ::continue::
  end
  return { statusMap = gitStatusMap, untrackedDirs = untrackedDirs }
end

local function updateGitStatus(buf_id)
  local MiniFiles = require("mini.files")
  local entry = MiniFiles.get_fs_entry(buf_id, 1)
  if not entry then return end
  local cwd = vim.fs.root(entry.path, ".git")
  if not cwd then return end

  local currentTime = os.time()
  if gitStatusCache[cwd] and currentTime - gitStatusCache[cwd].time < cacheTimeout then
    updateMiniWithGit(buf_id, gitStatusCache[cwd].statusMap)
  elseif pendingFetches[cwd] then
    -- Fetch already in-flight — queue this buffer for update when it completes
    table.insert(pendingFetches[cwd], buf_id)
  else
    pendingFetches[cwd] = { buf_id }
    fetchGitStatus(cwd, function(content)
      local waiting = pendingFetches[cwd] or {}
      pendingFetches[cwd] = nil
      if not content then return end
      local gitStatusMap = parseGitStatus(content)
      gitStatusCache[cwd] = { time = os.time(), statusMap = gitStatusMap }
      for _, waiting_buf in ipairs(waiting) do
        updateMiniWithGit(waiting_buf, gitStatusMap)
      end
    end)
  end
end

local function clearCache()
  gitStatusCache = {}
  pendingFetches = {}
end

local M = {}

function M.setup()
  local group = api.nvim_create_augroup("MiniFiles_git", { clear = true })

  -- MiniFilesExplorerOpen has no data — rely on MiniFilesBufferUpdate instead
  -- which fires for each visible buffer and provides data.buf_id

  api.nvim_create_autocmd("User", {
    group = group,
    pattern = "MiniFilesExplorerClose",
    callback = clearCache,
  })

  api.nvim_create_autocmd("User", {
    group = group,
    pattern = "MiniFilesBufferUpdate",
    callback = function(args)
      updateGitStatus(args.data.buf_id)
    end,
  })

  -- Invalidate cache when files are changed through mini.files
  api.nvim_create_autocmd("User", {
    group = group,
    pattern = {
      "MiniFilesActionCreate",
      "MiniFilesActionDelete",
      "MiniFilesActionRename",
      "MiniFilesActionCopy",
      "MiniFilesActionMove",
    },
    callback = clearCache,
  })
end

return M
