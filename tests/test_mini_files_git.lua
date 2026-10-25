local root = assert(arg[1])
local api = vim.api
local fixture = vim.fn.tempname() .. " mini files git"
local originalSystem = vim.system
local originalConfirm = vim.fn.confirm
local requests = {}
local ns = api.nvim_create_namespace("mini_files_git")
local MiniFiles

local function equal(actual, expected)
  assert(vim.deep_equal(actual, expected), vim.inspect({ actual = actual, expected = expected }))
end

local function waitFor(check)
  assert(vim.wait(2000, check, 10), "Timed out waiting for mini.files Git decorations")
end

local function git(...)
  local result = originalSystem(vim.list_extend({ "git", "-C", fixture }, { ... }), { text = true }):wait()
  assert(result.code == 0, result.stderr)
  return result.stdout
end

local function event(pattern, buffer)
  api.nvim_exec_autocmds("User", { pattern = pattern, data = { buf_id = buffer } })
end

local function row(buffer, name)
  for line = 1, api.nvim_buf_line_count(buffer) do
    local entry = MiniFiles.get_fs_entry(buffer, line)
    if entry and entry.name == name then
      return line
    end
  end
  error("Missing mini.files entry: " .. name)
end

local function decorations(buffer, name)
  local line = row(buffer, name) - 1
  local result = {}
  for _, mark in ipairs(api.nvim_buf_get_extmarks(buffer, ns, { line, 0 }, { line, -1 }, { details = true })) do
    if mark[4].virt_text then
      result.status = mark[4]
      result.column = mark[3]
    else
      result.name = mark[4]
    end
  end
  return result
end

local function respond(request, output, code)
  request.callback({ code = code or 0, stdout = output })
  vim.wait(20)
end

local function refresh(buffer, output)
  event("MiniFilesExplorerClose", buffer)
  event("MiniFilesBufferUpdate", buffer)
  respond(requests[#requests], output)
  waitFor(function()
    return decorations(buffer, "clean.txt").status ~= nil
  end)
end

local ok, err = xpcall(function()
  vim.o.columns, vim.o.lines = 120, 40
  vim.o.termguicolors = true
  vim.g.theme = {
    foreground = "#eeeeee",
    green = "#22cc22",
    red = "#ee2222",
    yellow = "#eeee22",
    comment = "#888888",
  }
  local lazy = vim.fn.stdpath("data") .. "/lazy/"
  vim.opt.runtimepath:append(lazy .. "mini.files")
  vim.opt.runtimepath:append(lazy .. "mini.icons")
  vim.opt.runtimepath:append(root .. "/config/nvim")
  require("mini.icons").setup()
  MiniFiles = require("mini.files")
  MiniFiles.setup({ content = {
    filter = function(entry)
      return entry.name ~= ".git"
    end,
  } })
  require("util.mini-files.git").setup()
  require("util.mini-files.symlinks").setup()

  vim.fn.mkdir(fixture, "p")
  git("init", "--quiet")
  local cases = {
    { " M", "unstaged.txt", "Normal", "Normal", "Unstaged" },
    { "M ", "staged.txt", "Staged", "Staged", "Staged" },
    { "MM", "mixed.txt", "Mixed", "Staged", "Unstaged" },
    { "A ", "added.txt", "Staged", "Staged", "Staged" },
    { "AM", "added modified.txt", "Mixed", "Staged", "Unstaged" },
    { "AD", "added-deleted.txt", "Mixed", "Staged", "Unstaged" },
    { " D", "deleted.txt", "Normal", "Normal", "Unstaged" },
    { "D ", "staged-delete.txt", "Staged", "Staged", "Staged" },
    { "R ", "renamed.txt", "Staged", "Staged", "Staged" },
    { "C ", "copied.txt", "Staged", "Staged", "Staged" },
    { " T", "type.txt", "Normal", "Normal", "Unstaged" },
    { "T ", "staged-type.txt", "Staged", "Staged", "Staged" },
    { "??", "untracked.txt", "Normal", "Unstaged", "Unstaged" },
    { "!!", "ignored.txt", "Ignored", "Ignored", "Ignored" },
    { "DD", "conflict-dd.txt", "Mixed", "Staged", "Unstaged" },
    { "AU", "conflict-au.txt", "Mixed", "Staged", "Unstaged" },
    { "UD", "conflict-ud.txt", "Normal", "Staged", "Unstaged" },
    { "UA", "conflict-ua.txt", "Normal", "Staged", "Unstaged" },
    { "DU", "conflict-du.txt", "Mixed", "Staged", "Unstaged" },
    { "AA", "conflict-aa.txt", "Mixed", "Staged", "Unstaged" },
    { "UU", "conflict-uu.txt", "Normal", "Staged", "Unstaged" },
  }
  local records = {}
  for _, case in ipairs(cases) do
    vim.fn.writefile({ "fixture" }, fixture .. "/" .. case[2])
    table.insert(records, case[1] .. " " .. case[2] .. "\0")
    if case[1] == "R " or case[1] == "C " then
      table.insert(records, "previous name.txt\0")
    end
  end
  vim.fn.writefile({ "clean" }, fixture .. "/clean.txt")
  vim.fn.mkdir(fixture .. "/folder", "p")
  vim.fn.mkdir(fixture .. "/new-folder/nested", "p")
  vim.fn.writefile({ "child" }, fixture .. "/new-folder/nested/child.txt")
  assert(vim.uv.fs_symlink("staged.txt", fixture .. "/link.txt"))
  table.insert(records, "M  link.txt\0")
  local output = table.concat(records)

  rawset(vim, "system", function(command, options, callback)
    equal(command, { "git", "--no-optional-locks", "status", "--ignored", "--porcelain=v1", "-z" })
    table.insert(requests, { callback = callback, cwd = options.cwd })
  end)
  MiniFiles.open(fixture, false)
  local buffer = api.nvim_get_current_buf()
  local before = api.nvim_buf_get_lines(buffer, 0, -1, false)
  equal(#requests, 1)
  respond(requests[1], output)
  waitFor(function()
    return decorations(buffer, "clean.txt").status ~= nil
  end)
  equal(api.nvim_buf_get_lines(buffer, 0, -1, false), before)

  for _, case in ipairs(cases) do
    local mark = decorations(buffer, case[2])
    equal(mark.status.virt_text, {
      { case[1]:sub(1, 1), "MiniFilesGit" .. case[4] },
      { case[1]:sub(2, 2), "MiniFilesGit" .. case[5] },
      { " ", "MiniFilesGit" .. case[3] },
    })
    equal(mark.status.virt_text_pos, "inline")
    equal(mark.status.hl_mode, "replace")
    equal(mark.name.hl_group, "MiniFilesGit" .. case[3])
    equal(mark.name.priority, 4097)
    equal(mark.column, #assert(before[row(buffer, case[2])]:match("^/%d+/")))
    assert(mark.status.sign_text == nil)
  end
  local clean = decorations(buffer, "clean.txt")
  equal(clean.status.virt_text, {
    { " ", "MiniFilesGitNormal" },
    { " ", "MiniFilesGitNormal" },
    { " ", "MiniFilesGitNormal" },
  })
  assert(clean.name == nil)

  local linkRow = row(buffer, "link.txt") - 1
  local linkNs = api.nvim_create_namespace("mini_files_symlinks")
  waitFor(function()
    return #api.nvim_buf_get_extmarks(buffer, linkNs, { linkRow, 0 }, { linkRow, -1 }, {}) > 0
  end)
  local linkMarks = api.nvim_buf_get_extmarks(buffer, linkNs, { linkRow, 0 }, { linkRow, -1 }, { details = true })
  local arrow = false
  for _, mark in ipairs(linkMarks) do
    if mark[4].sign_text then
      arrow = vim.trim(mark[4].sign_text) == "↩"
    else
      assert(decorations(buffer, "link.txt").name.priority > mark[4].priority)
    end
  end
  assert(arrow)
  local referenceNs = api.nvim_create_namespace("mini_files_git_color_reference")
  local cleanRow = row(buffer, "clean.txt")
  api.nvim_buf_set_extmark(buffer, referenceNs, cleanRow - 1, 0, {
    virt_text = { { "RG", "MiniFilesGitUnstaged" }, { "GR", "MiniFilesGitStaged" } },
    virt_text_pos = "eol",
    hl_mode = "replace",
  })
  vim.wo.cursorline = false
  vim.cmd.redraw()
  local referencePosition = vim.fn.screenpos(api.nvim_get_current_win(), cleanRow, 1)
  local referenceAttributes = {}
  for column = 1, vim.o.columns - 3 do
    if
      vim.fn.screenstring(referencePosition.row, column) == "R"
      and vim.fn.screenstring(referencePosition.row, column + 1) == "G"
      and vim.fn.screenstring(referencePosition.row, column + 2) == "G"
    then
      referenceAttributes.red = vim.fn.screenattr(referencePosition.row, column)
      referenceAttributes.green = vim.fn.screenattr(referencePosition.row, column + 2)
      break
    end
  end
  assert(referenceAttributes.red and referenceAttributes.green)
  assert(referenceAttributes.red ~= referenceAttributes.green)
  local filenameColumns = {}
  for _, name in ipairs({ "clean.txt", "staged.txt", "unstaged.txt", "mixed.txt" }) do
    local line = row(buffer, name)
    local text = api.nvim_buf_get_lines(buffer, line - 1, line, false)[1]
    local _, start = text:find("^/%d+/.-/")
    table.insert(filenameColumns, vim.fn.screenpos(api.nvim_get_current_win(), line, start + 1).col)
    local position = vim.fn.screenpos(api.nvim_get_current_win(), line, start + 1)
    local screen = {}
    for column = 1, vim.o.columns do
      table.insert(screen, vim.fn.screenstring(position.row, column))
    end
    local expected = ({ ["clean.txt"] = "  ", ["staged.txt"] = "M ", ["unstaged.txt"] = " M", ["mixed.txt"] = "MM" })[name]
    local icon = assert(text:match("^/%d+/(.-)/"))
    local statusColumn =
      assert(table.concat(screen):find(expected .. " " .. icon .. name, 1, true), table.concat(screen))
    statusColumn = vim.fn.strchars(table.concat(screen):sub(1, statusColumn - 1)) + 1
    for offset = 0, 1 do
      if expected:sub(offset + 1, offset + 1) == "M" then
        equal(
          vim.fn.screenattr(position.row, statusColumn + offset),
          offset == 0 and referenceAttributes.green or referenceAttributes.red
        )
      end
    end
  end
  for _, column in ipairs(filenameColumns) do
    equal(column, filenameColumns[1])
    assert(column > 0)
  end
  api.nvim_buf_clear_namespace(buffer, referenceNs, 0, -1)

  local count = #requests
  event("MiniFilesBufferUpdate", buffer)
  vim.wait(20)
  equal(#requests, count)
  for _, action in ipairs({ "Create", "Delete", "Rename", "Copy", "Move" }) do
    event("MiniFilesAction" .. action, buffer)
    event("MiniFilesBufferUpdate", buffer)
    equal(#requests, count + 1)
    count = #requests
    respond(requests[count], output)
  end
  event("MiniFilesExplorerClose", buffer)
  event("MiniFilesBufferUpdate", buffer)
  local stale = requests[#requests]
  event("MiniFilesExplorerClose", buffer)
  event("MiniFilesBufferUpdate", buffer)
  respond(stale, "!! staged.txt\0")
  equal(api.nvim_buf_get_extmarks(buffer, ns, 0, -1, {}), {})
  respond(requests[#requests], output)
  equal(decorations(buffer, "staged.txt").name.hl_group, "MiniFilesGitStaged")

  event("MiniFilesExplorerClose", buffer)
  event("MiniFilesBufferUpdate", buffer)
  respond(requests[#requests], "", 1)
  equal(api.nvim_buf_get_extmarks(buffer, ns, 0, -1, {}), {})
  local failedCount = #requests
  event("MiniFilesBufferUpdate", buffer)
  equal(#requests, failedCount + 1)
  respond(requests[#requests], output)
  equal(decorations(buffer, "staged.txt").name.hl_group, "MiniFilesGitStaged")

  for _, descendants in ipairs({ "M  folder/a\0 M folder/b\0", " M folder/b\0M  folder/a\0" }) do
    refresh(buffer, output .. descendants)
    equal(decorations(buffer, "folder").name.hl_group, "MiniFilesGitMixed")
  end
  refresh(buffer, output .. "M  folder/a\0!! folder/ignored\0")
  equal(decorations(buffer, "folder").name.hl_group, "MiniFilesGitStaged")

  vim.g.theme = { foreground = "#111111", green = "#008800", red = "#aa0000", yellow = "#aa8800", comment = "#666666" }
  api.nvim_exec_autocmds("ColorScheme", {})
  for suffix, key in pairs({
    Normal = "foreground",
    Staged = "green",
    Unstaged = "red",
    Mixed = "yellow",
    Ignored = "comment",
  }) do
    equal(api.nvim_get_hl(0, { name = "MiniFilesGit" .. suffix }).fg, tonumber(vim.g.theme[key]:sub(2), 16))
  end

  MiniFiles.close()
  MiniFiles.open(fixture .. "/new-folder/nested", false)
  local nested = api.nvim_get_current_buf()
  respond(requests[#requests], "?? new-folder/\0")
  equal(decorations(nested, "child.txt").status.virt_text[1], { "?", "MiniFilesGitUnstaged" })
  equal(decorations(nested, "child.txt").name.hl_group, "MiniFilesGitNormal")
  MiniFiles.close()

  rawset(vim, "system", originalSystem)
  git("add", "staged.txt", "mixed.txt", "link.txt")
  vim.fn.writefile({ "changed after staging" }, fixture .. "/mixed.txt")
  MiniFiles.open(fixture, false)
  buffer = api.nvim_get_current_buf()
  waitFor(function()
    return decorations(buffer, "staged.txt").name ~= nil
  end)
  equal(decorations(buffer, "staged.txt").name.hl_group, "MiniFilesGitStaged")
  equal(decorations(buffer, "mixed.txt").name.hl_group, "MiniFilesGitMixed")
  equal(decorations(buffer, "untracked.txt").name.hl_group, "MiniFilesGitNormal")

  api.nvim_win_set_cursor(0, { row(buffer, "folder"), 0 })
  MiniFiles.go_in()
  equal(MiniFiles.get_explorer_state().branch[2], fixture .. "/folder")
  MiniFiles.go_out()
  buffer = api.nvim_get_current_buf()
  api.nvim_exec_autocmds("TextChanged", { buffer = buffer })
  local renameRow = row(buffer, "untracked.txt")
  local oldLine = api.nvim_buf_get_lines(buffer, renameRow - 1, renameRow, false)[1]
  local newLine, replacements = oldLine:gsub("untracked%.txt$", "renamed by mini.txt")
  equal(replacements, 1)
  api.nvim_buf_set_lines(buffer, renameRow - 1, renameRow, false, { newLine })
  api.nvim_exec_autocmds("TextChanged", { buffer = buffer })
  rawset(vim.fn, "confirm", function()
    return 1
  end)
  assert(MiniFiles.synchronize())
  assert(vim.uv.fs_stat(fixture .. "/renamed by mini.txt"))
  assert(not vim.uv.fs_stat(fixture .. "/untracked.txt"))
  equal(vim.fn.readfile(fixture .. "/renamed by mini.txt"), { "fixture" })
  MiniFiles.close()
end, debug.traceback)

rawset(vim, "system", originalSystem)
rawset(vim.fn, "confirm", originalConfirm)
if MiniFiles then
  pcall(MiniFiles.close)
end
assert(originalSystem({ "trash", fixture }, { text = true }):wait().code == 0)
assert(ok, err)
print(
  "PASS: Lazygit-style statuses, filenames, directories, cache invalidation, symlinks, alignment and mini.files actions"
)
