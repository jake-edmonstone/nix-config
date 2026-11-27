-- TODO: remove when native Neovim OSC 7577 support replaces this (neovim/neovim#42995).
local token = vim.env.OSC7577_TOKEN
vim.env.OSC7577_TOKEN = nil
if #token < 22 or #token > 64 or not token:match("^[A-Za-z0-9_-]+$") then
  return
end

local api, uv = vim.api, vim.uv
local group = api.nvim_create_augroup("RexResume", { clear = true })
local dir = vim.fn.stdpath("state") .. "/osc7577"
local path, timer, reported_at
local leaving = false

local function owner()
  local uis = api.nvim_list_uis()
  local ui = uis[1]
  if #uis ~= 1 or not ui.stdout_tty then
    return
  end
  local chan = api.nvim_get_chan_info(ui.chan)
  local client = chan.client
  local pid = uv.os_getppid()
  if chan.stream == "stdio" and client and client.name == "nvim-tui" and (client.attributes or {}).pid == pid then
    return pid
  end
end

local function report(pid, time, fields)
  local body = ("pid=%d:time=%d:%s"):format(pid, time, fields)
  local data = "\27]7577;" .. body .. ":mac=" .. vim.fn.sha256(body .. ":" .. token) .. "\27\\"
  if #data <= 2048 then
    api.nvim_ui_send(data)
    return true
  end
end

local function save()
  local pid = owner()
  if leaving or not pid or vim.fn.mode():find("^[cr]") or vim.fn.getcmdwintype() ~= "" then
    return
  end
  vim.fn.mkdir(dir, "p", 448) -- 0700
  local info = uv.fs_lstat(dir)
  if not info or info.type ~= "directory" or bit.band(info.mode, 63) ~= 0 then
    return
  end
  local fd, tmp = uv.fs_mkstemp(dir .. "/snapshot-XXXXXX")
  if not fd then
    return
  end
  uv.fs_close(fd)

  -- Keep Persistence's project session separate and never restart terminal jobs.
  local session, options = vim.v.this_session, vim.o.sessionoptions
  vim.o.sessionoptions = "blank,buffers,curdir,folds,tabpages,winsize"
  local ok = pcall(vim.cmd, "silent noautocmd mksession! " .. vim.fn.fnameescape(tmp))
  vim.v.this_session, vim.o.sessionoptions = session, options
  path = path or (tmp .. ".vim")
  if not ok or not uv.fs_rename(tmp, path) then
    return
  end

  if not reported_at and not path:find("[%z\1-\31\127]") and not path:find("\194[\128-\159]") then
    local argv = vim.tbl_map(vim.base64.encode, { "nvim", "-S", path })
    local now = os.time()
    if report(pid, now, "argv=" .. table.concat(argv, ",")) then
      reported_at = now
    end
  end
end

api.nvim_create_autocmd("VimEnter", {
  group = group,
  once = true,
  callback = function()
    vim.schedule(save)
  end,
})
api.nvim_create_autocmd({ "BufWinEnter", "BufDelete", "WinNew", "WinClosed", "WinResized", "TabNew", "TabClosed", "DirChanged" }, {
  group = group,
  callback = function()
    if not path or leaving then
      return
    end
    timer = timer or uv.new_timer()
    timer:start(1000, 0, vim.schedule_wrap(save))
  end,
})
api.nvim_create_autocmd({ "FocusLost", "VimSuspend" }, { group = group, callback = save })
api.nvim_create_autocmd("VimLeavePre", {
  group = group,
  callback = function()
    leaving = true
    if timer then
      timer:close()
    end
    local pid, now = owner(), os.time()
    if pid and vim.v.dying == 0 and vim.v.exitreason == "quit" and reported_at and now > reported_at then
      report(pid, now, "clear=1")
    end
  end,
})
