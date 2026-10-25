-- Git status integration for mini.files

local api = vim.api
local ns = api.nvim_create_namespace("mini_files_git")
local function setHighlights()
  local palette = vim.g.theme
  api.nvim_set_hl(0, "MiniFilesGitNormal", { fg = palette.foreground })
  api.nvim_set_hl(0, "MiniFilesGitStaged", { fg = palette.green })
  api.nvim_set_hl(0, "MiniFilesGitUnstaged", { fg = palette.red })
  api.nvim_set_hl(0, "MiniFilesGitMixed", { fg = palette.yellow })
  api.nvim_set_hl(0, "MiniFilesGitIgnored", { fg = palette.comment })
end

local gitStatusCache = {}
local pendingFetches = {}
local cacheTimeout = 10

local function staging(status)
  local index = status:sub(1, 1)
  return index ~= " " and index ~= "U" and index ~= "?", status:sub(2, 2) ~= " "
end

local function filenameHighlight(status, directoryState)
  if status == "!!" then
    return "MiniFilesGitIgnored"
  end
  local staged, unstaged = staging(status)
  if directoryState then
    staged, unstaged = directoryState.staged, directoryState.unstaged
  end
  if staged then
    return unstaged and "MiniFilesGitMixed" or "MiniFilesGitStaged"
  end
  return "MiniFilesGitNormal"
end

local statusPriority = {
  ["UU"] = 6,
  ["UA"] = 6,
  ["U "] = 6,
  ["MM"] = 5,
  ["M "] = 5,
  [" M"] = 5,
  ["A "] = 4,
  ["AA"] = 4,
  ["AM"] = 4,
  ["AD"] = 4,
  ["R "] = 3,
  ["RM"] = 3,
  ["RD"] = 3,
  ["??"] = 2,
  [" D"] = 1,
  ["D "] = 1,
}

local function fetchGitStatus(cwd, callback)
  vim.system(
    { "git", "--no-optional-locks", "status", "--ignored", "--porcelain=v1", "-z" },
    { cwd = cwd },
    function(content)
      callback(content.code == 0 and content.stdout or nil)
    end
  )
end

local function addStatus(gitStatusMap, untrackedDirs, directoryStates, status, filePath)
  local isUntrackedDir = status == "??" and filePath:sub(-1) == "/"
  filePath = filePath:gsub("/$", "")
  if isUntrackedDir then
    untrackedDirs[filePath] = true
  end

  local parts = vim.split(filePath, "/", { plain = true })
  gitStatusMap[filePath] = status

  if status == "!!" then
    return
  end
  local priority = statusPriority[status] or 0
  local staged, unstaged = staging(status)
  for i = 1, #parts - 1 do
    local currentKey = table.concat(parts, "/", 1, i)
    local state = directoryStates[currentKey] or { staged = false, unstaged = false }
    state.staged = state.staged or staged
    state.unstaged = state.unstaged or unstaged
    directoryStates[currentKey] = state
    local existing = gitStatusMap[currentKey]
    if not existing or (statusPriority[existing] or 0) < priority then
      gitStatusMap[currentKey] = status
    end
  end
end

local function parseGitStatus(content)
  local gitStatusMap = {}
  local untrackedDirs = {}
  local directoryStates = {}
  local offset = 1

  while offset <= #content do
    local terminator = content:find("\0", offset, true)
    if not terminator then
      break
    end
    local record = content:sub(offset, terminator - 1)
    offset = terminator + 1

    local status = record:sub(1, 2)
    local filePath = record:sub(4)
    if #status == 2 and filePath ~= "" then
      addStatus(gitStatusMap, untrackedDirs, directoryStates, status, filePath)

      -- In porcelain -z output, rename/copy records are followed by the old
      -- path as a second NUL-delimited field. The first path is the destination.
      if status:sub(1, 1) == "R" or status:sub(1, 1) == "C" then
        local oldPathEnd = content:find("\0", offset, true)
        if not oldPathEnd then
          break
        end
        offset = oldPathEnd + 1
      end
    end
  end

  return { statusMap = gitStatusMap, untrackedDirs = untrackedDirs, directoryStates = directoryStates }
end

local function updateMiniWithGit(buf_id, cwd, gitStatus)
  vim.schedule(function()
    if not api.nvim_buf_is_valid(buf_id) then
      return
    end

    local MiniFiles = require("mini.files")
    local firstEntry = MiniFiles.get_fs_entry(buf_id, 1)
    if not firstEntry then
      return
    end
    local currentRoot = vim.fs.root(firstEntry.path, ".git")
    if not currentRoot or vim.fs.normalize(currentRoot) ~= vim.fs.normalize(cwd) then
      return
    end

    api.nvim_buf_clear_namespace(buf_id, ns, 0, -1)
    local nlines = api.nvim_buf_line_count(buf_id)
    local escapedCwd = vim.pesc(vim.fs.normalize(cwd))
    local lines = api.nvim_buf_get_lines(buf_id, 0, nlines, false)
    local statusMapByPath = gitStatus.statusMap or {}
    local untrackedDirs = gitStatus.untrackedDirs or {}
    local directoryStates = gitStatus.directoryStates or {}

    for i = 1, nlines do
      local entry = MiniFiles.get_fs_entry(buf_id, i)
      if not entry then
        break
      end

      local relativePath = entry.path:gsub("^" .. escapedCwd .. "/", "")
      local status = statusMapByPath[relativePath]
      if not status then
        local parent = relativePath
        while true do
          parent = parent:match("^(.+)/[^/]+$")
          if not parent then
            break
          end
          if untrackedDirs[parent] then
            status = "??"
            break
          end
        end
      end

      local line = lines[i]
      local _, prefixStart = line:find("^/%d+/")
      local _, nameStart = line:find("^/%d+/.-/")
      if prefixStart and nameStart then
        local nameHighlight = status and filenameHighlight(status, directoryStates[relativePath])
          or "MiniFilesGitNormal"
        local first, second = (status or "  "):sub(1, 1), (status or "  "):sub(2, 2)
        local firstHighlight = first == " " and nameHighlight or "MiniFilesGitStaged"
        local secondHighlight = second == " " and nameHighlight or "MiniFilesGitUnstaged"
        if status == "??" then
          firstHighlight = "MiniFilesGitUnstaged"
        elseif status == "!!" then
          firstHighlight, secondHighlight = "MiniFilesGitIgnored", "MiniFilesGitIgnored"
        end
        api.nvim_buf_set_extmark(buf_id, ns, i - 1, prefixStart, {
          virt_text = { { first, firstHighlight }, { second, secondHighlight }, { " ", nameHighlight } },
          virt_text_pos = "inline",
          hl_mode = "replace",
          right_gravity = false,
        })

        if status then
          api.nvim_buf_set_extmark(buf_id, ns, i - 1, nameStart, {
            end_col = #line,
            hl_group = nameHighlight,
            priority = 4097,
            right_gravity = false,
          })
        end
      end
    end
  end)
end

local function updateGitStatus(buf_id)
  if api.nvim_buf_is_valid(buf_id) then
    api.nvim_buf_clear_namespace(buf_id, ns, 0, -1)
  end

  local MiniFiles = require("mini.files")
  local entry = MiniFiles.get_fs_entry(buf_id, 1)
  if not entry then
    return
  end
  local cwd = vim.fs.root(entry.path, ".git")
  if not cwd then
    return
  end

  local currentTime = os.time()
  if gitStatusCache[cwd] and currentTime - gitStatusCache[cwd].time < cacheTimeout then
    updateMiniWithGit(buf_id, cwd, gitStatusCache[cwd].status)
    return
  end

  if pendingFetches[cwd] then
    table.insert(pendingFetches[cwd], buf_id)
    return
  end

  local waiting = { buf_id }
  pendingFetches[cwd] = waiting
  fetchGitStatus(cwd, function(content)
    -- Cache invalidation replaces pendingFetches. An older callback must not
    -- consume a newer request's waiting buffers.
    if pendingFetches[cwd] ~= waiting then
      return
    end
    pendingFetches[cwd] = nil
    if not content then
      return
    end

    local status = parseGitStatus(content)
    gitStatusCache[cwd] = { time = os.time(), status = status }
    for _, waitingBuf in ipairs(waiting) do
      updateMiniWithGit(waitingBuf, cwd, status)
    end
  end)
end

local function clearCache()
  gitStatusCache = {}
  pendingFetches = {}
end

local M = {}

function M.setup()
  local group = api.nvim_create_augroup("MiniFiles_git", { clear = true })
  setHighlights()

  api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = setHighlights,
  })

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
