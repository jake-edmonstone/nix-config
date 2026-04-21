-- Symlink indicators for mini.files (async, batched)
--
-- Previously we fired one uv.fs_lstat per directory entry, which on network-
-- backed homes (Cerebras EFS, UWaterloo CephFS) produces a burst of syscalls
-- on every buffer update. readdir(2) already returns d_type on most modern
-- filesystems, so uv.fs_scandir gives us the full set of links in one syscall.
-- We still fall back to fs_lstat for filesystems that report d_type = nil
-- (older NFS setups, some tmpfs configs).

local api = vim.api
local ns = api.nvim_create_namespace("mini_files_symlinks")
local uv = vim.uv

local function markSymlinks(buf_id)
  api.nvim_buf_clear_namespace(buf_id, ns, 0, -1)
  local MiniFiles = require("mini.files")
  if api.nvim_buf_line_count(buf_id) == 0 then return end

  -- Every line in a mini.files buffer lives in the same directory; derive the
  -- parent path from the first entry's path.
  local first = MiniFiles.get_fs_entry(buf_id, 1)
  if not first then return end
  local parent = vim.fn.fnamemodify(first.path, ":h")

  uv.fs_scandir(parent, function(scan_err, req)
    if scan_err or not req then return end

    local links = {}
    local unknown = {}
    while true do
      local name, t = uv.fs_scandir_next(req)
      if not name then break end
      if t == "link" then
        links[name] = true
      elseif t == nil then
        unknown[#unknown + 1] = name
      end
    end

    -- Filesystems that don't return d_type in readdir: one fs_lstat per
    -- unknown entry. Rare on modern disks; common on some network mounts.
    local pending = #unknown
    local function afterUnknownResolved()
      if next(links) == nil then return end
      vim.schedule(function()
        if not api.nvim_buf_is_valid(buf_id) then return end
        -- Re-read line count inside schedule: the buffer may have been
        -- replaced if the user navigated to a sibling dir between scandir
        -- dispatch and this callback firing.
        local nlines = api.nvim_buf_line_count(buf_id)
        for i = 1, nlines do
          local entry = MiniFiles.get_fs_entry(buf_id, i)
          if not entry then break end
          if links[entry.name] then
            local line_idx = i - 1
            api.nvim_buf_set_extmark(buf_id, ns, line_idx, 0, {
              sign_text = "↩",
              sign_hl_group = "MiniDiffSignDelete",
              priority = 1,
            })
            local line = api.nvim_buf_get_lines(buf_id, line_idx, line_idx + 1, false)[1]
            if line then
              local _, prefix_end = line:find("^/%d+/.-/")
              if prefix_end then
                local nameStart = line:find(vim.pesc(entry.name), prefix_end + 1)
                if nameStart then
                  api.nvim_buf_set_extmark(buf_id, ns, line_idx, nameStart - 1, {
                    end_col = nameStart + #entry.name - 1,
                    hl_group = "MiniDiffSignDelete",
                  })
                end
              end
            end
          end
        end
      end)
    end

    if pending == 0 then
      afterUnknownResolved()
    else
      for _, name in ipairs(unknown) do
        uv.fs_lstat(parent .. "/" .. name, function(_, stat)
          if stat and stat.type == "link" then links[name] = true end
          pending = pending - 1
          if pending == 0 then afterUnknownResolved() end
        end)
      end
    end
  end)
end

local M = {}

function M.setup()
  local group = api.nvim_create_augroup("MiniFiles_symlinks", { clear = true })

  api.nvim_create_autocmd("User", {
    group = group,
    pattern = "MiniFilesBufferUpdate",
    callback = function(args)
      markSymlinks(args.data.buf_id)
    end,
  })
end

return M
