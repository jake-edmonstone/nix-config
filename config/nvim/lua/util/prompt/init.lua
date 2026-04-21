local M = {}

local api = vim.api

--- Context providers — each returns a string or nil.
--- Output uses Claude Code's @file#Lstart-end mention syntax (per VS Code extension docs).

--- Returns the relative path of the current buffer, or nil for unnamed/special buffers.
local function buf_path()
  local name = api.nvim_buf_get_name(0)
  if name == "" then return nil end
  return vim.fn.fnamemodify(name, ":.")
end

M.contexts = {
  ["@buffer"] = function()
    local path = buf_path()
    if not path then return nil end
    return "@" .. path
  end,
  ["@cursor"] = function()
    local path = buf_path()
    if not path then return nil end
    local line = api.nvim_win_get_cursor(0)[1]
    return string.format("@%s#L%d", path, line)
  end,
  ["@selection"] = function()
    local path = buf_path()
    if not path then return nil end
    local s = vim.fn.getpos("'<")[2]
    local e = vim.fn.getpos("'>")[2]
    if s == 0 and e == 0 then return nil end
    if s > e then s, e = e, s end
    return string.format("@%s#L%d-%d", path, s, e)
  end,
  ["@diagnostic"] = function()
    local path = buf_path()
    if not path then return nil end
    local lnum = api.nvim_win_get_cursor(0)[1] - 1
    local diags = vim.diagnostic.get(0, { lnum = lnum })
    if #diags == 0 then return nil end
    local parts = {}
    for _, d in ipairs(diags) do
      parts[#parts + 1] = string.format("@%s#L%d: %s", path, d.lnum + 1, d.message:gsub("%s+", " "))
    end
    return table.concat(parts, "; ")
  end,
  ["@diagnostics"] = function()
    local path = buf_path()
    if not path then return nil end
    local diags = vim.diagnostic.get(0)
    if #diags == 0 then return nil end
    local parts = {}
    for _, d in ipairs(diags) do
      parts[#parts + 1] = string.format("@%s#L%d: %s", path, d.lnum + 1, d.message:gsub("%s+", " "))
    end
    return table.concat(parts, "\n")
  end,
  -- @diff is resolved ASYNCHRONOUSLY in inject() below — git diff can take
  -- seconds on slow/large repos and a synchronous :wait() blocks the editor.
  -- Keep a stub here so placeholder_names includes "@diff" for highlighting.
  ["@diff"] = function() return nil end,
}

-- Computed once — contexts is static
local placeholder_names = vim.tbl_keys(M.contexts)
table.sort(placeholder_names, function(a, b) return #a > #b end)

local placeholder_ns = api.nvim_create_namespace("prompt_placeholders")

-- Highlight groups — nvim_set_hl is idempotent, no need for hlexists guard
local hl = "DraculaPrompt"
local hl_border = "DraculaPromptBorder"
local hl_title = "DraculaPromptTitle"
local hl_placeholder = "DraculaPromptPlaceholder"
api.nvim_set_hl(0, hl, { bg = "#282A36" })
api.nvim_set_hl(0, hl_border, { fg = "#BD93F9", bg = "#282A36" })
api.nvim_set_hl(0, hl_title, { fg = "#282A36", bg = "#BD93F9", bold = true })
api.nvim_set_hl(0, hl_placeholder, { fg = "#BD93F9", bold = true })

--- Replace @placeholders with actual context, longest-first to avoid partial matches.
--- Invokes cb(result) when done. Asynchronous because @diff shells out to git,
--- which can take multiple seconds on large repos; we don't want to freeze the
--- editor on `:wait()`. All other placeholders resolve synchronously.
local function inject(prompt, source_win, cb)
  api.nvim_set_current_win(source_win)
  local failed = {}

  -- Snapshot @diff presence on the ORIGINAL prompt so a sync placeholder whose
  -- resolved value happens to contain the literal "@diff" can't trigger a
  -- spurious git subprocess.
  local has_diff = prompt:find("@diff", 1, true) ~= nil

  -- Resolve synchronous placeholders first. @diff is handled below.
  for _, key in ipairs(placeholder_names) do
    if key ~= "@diff" and prompt:find(key, 1, true) then
      local val = M.contexts[key]()
      if val then
        prompt = prompt:gsub(vim.pesc(key), function() return val end)
      else
        failed[#failed + 1] = key
      end
    end
  end

  local function finalize()
    if #failed > 0 then
      vim.notify("Could not resolve: " .. table.concat(failed, ", "), vim.log.levels.WARN)
    end
    cb(prompt)
  end

  if has_diff then
    vim.system({ "git", "--no-pager", "diff" }, { text = true }, function(obj)
      vim.schedule(function()
        if obj.code == 0 and obj.stdout and obj.stdout ~= "" then
          prompt = prompt:gsub(vim.pesc("@diff"), function() return obj.stdout end)
        else
          failed[#failed + 1] = "@diff"
        end
        finalize()
      end)
    end)
  else
    finalize()
  end
end

local prompts = {
  { name = "explain", desc = "Explain code near cursor", prompt = "Explain @cursor and its context" },
  { name = "document", desc = "Document selection", prompt = "Add documentation comments for @selection" },
  { name = "fix", desc = "Fix diagnostics", prompt = "Fix these @diagnostics" },
  { name = "fix_line", desc = "Fix line diagnostic", prompt = "Fix this @diagnostic" },
  { name = "optimize", desc = "Optimize selection", prompt = "Optimize @selection for performance and readability" },
  { name = "review", desc = "Review buffer", prompt = "Review @buffer for correctness and readability" },
}

--- Open a floating prompt window with wrapping support.
---@param default? string Text to prefill
function M.ask(default)
  local source_win = api.nvim_get_current_win()

  -- figure out where the context lines are on screen so we don't cover them
  local float_height = 3 -- border (1) + content (1) + border (1)
  local editor_h = vim.o.lines - vim.o.cmdheight
  local cursor_screen = vim.fn.screenpos(source_win, vim.fn.line("."), 1).row
  local sel_start, sel_end = cursor_screen, cursor_screen
  local vstart = vim.fn.getpos("'<")[2]
  local vend = vim.fn.getpos("'>")[2]
  if vstart > 0 and vend > 0 then
    local sp_s = vim.fn.screenpos(source_win, math.min(vstart, vend), 1).row
    local sp_e = vim.fn.screenpos(source_win, math.max(vstart, vend), 1).row
    if sp_s > 0 then sel_start = sp_s end
    if sp_e > 0 then sel_end = sp_e end
  end

  local gap = 1
  local float_row
  local space_below = editor_h - sel_end
  local space_above = sel_start - 1
  if space_below >= float_height + gap then
    float_row = sel_end + gap
  elseif space_above >= float_height + gap then
    float_row = sel_start - gap - float_height
  else
    float_row = math.floor(editor_h * 0.4)
  end

  local buf = api.nvim_create_buf(false, true)
  local width = math.floor(vim.o.columns * 0.5)
  local win = api.nvim_open_win(buf, true, {
    relative = "editor",
    row = float_row,
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = 1,
    border = "rounded",
    title = " 󰭻 Prompt ",
    title_pos = "center",
    footer = " <CR> send  <Esc> cancel ",
    footer_pos = "center",
  })

  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].winhl = "Normal:" .. hl .. ",FloatBorder:" .. hl_border .. ",FloatTitle:" .. hl_title .. ",FloatFooter:" .. hl_border
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].filetype = "prompt"

  if default then
    api.nvim_buf_set_lines(buf, 0, -1, false, { default })
    api.nvim_win_set_cursor(win, { 1, #default })
  end

  local max_height = math.floor(vim.o.lines * 0.4)

  local function resize()
    if not api.nvim_win_is_valid(win) then return end
    local h = api.nvim_win_text_height(win, {}).all
    -- In insert mode the cursor sits past the last char and may wrap to
    -- the next visual row, which text_height doesn't count.
    local mode = api.nvim_get_mode().mode
    if mode == "i" or mode == "R" then
      local cursor_row = api.nvim_win_get_cursor(win)[1]
      local line = api.nvim_buf_get_lines(buf, cursor_row - 1, cursor_row, false)[1] or ""
      if #line > 0 then
        local sp_last = vim.fn.screenpos(win, cursor_row, #line)
        local sp_past = vim.fn.screenpos(win, cursor_row, #line + 1)
        if sp_past.row > sp_last.row then
          h = h + 1
        end
      end
    end
    api.nvim_win_set_height(win, math.max(1, math.min(h, max_height)))
  end

  local function highlight()
    if not api.nvim_buf_is_valid(buf) then return end
    api.nvim_buf_clear_namespace(buf, placeholder_ns, 0, -1)
    local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
    for i, line in ipairs(lines) do
      for _, name in ipairs(placeholder_names) do
        local start = 1
        while true do
          local s, e = line:find(name, start, true)
          if not s then break end
          api.nvim_buf_set_extmark(buf, placeholder_ns, i - 1, s - 1, {
            end_col = e,
            hl_group = hl_placeholder,
          })
          start = e + 1
        end
      end
    end
  end

  -- Initial highlight for prefilled text
  highlight()

  local group = api.nvim_create_augroup("PromptFloat_" .. buf, { clear = true })
  api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    buffer = buf,
    callback = function()
      resize()
      highlight()
    end,
  })

  vim.cmd.startinsert({ bang = true })

  local function close()
    if api.nvim_win_is_valid(win) then api.nvim_win_close(win, true) end
    if api.nvim_buf_is_valid(buf) then api.nvim_buf_delete(buf, { force = true }) end
  end

  local function submit()
    local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
    local text = vim.trim(table.concat(lines, " "))
    close()
    if text == "" then return end
    if api.nvim_win_is_valid(source_win) then
      inject(text, source_win, function(result)
        vim.fn.setreg("+", result)
        vim.notify("Prompt copied to clipboard", vim.log.levels.INFO)
      end)
    end
  end

  local kopts = { buf = buf, silent = true }
  vim.keymap.set("n", "<CR>", submit, kopts)
  vim.keymap.set("n", "q", close, kopts)
  vim.keymap.set("n", "<Esc>", close, kopts)
end

--- Select from predefined prompts, or use one directly by name.
---@param name? string
function M.select_prompt(name)
  local source_win = api.nvim_get_current_win()

  local function apply(prompt_text)
    inject(prompt_text, source_win, function(result)
      vim.fn.setreg("+", result)
      vim.notify("Prompt copied to clipboard", vim.log.levels.INFO)
    end)
  end

  if name then
    for _, p in ipairs(prompts) do
      if p.name == name then
        apply(p.prompt)
        return
      end
    end
    vim.notify("Prompt '" .. name .. "' not found", vim.log.levels.WARN)
    return
  end

  local is_visual = api.nvim_get_mode().mode:match("[vV\22]")
  local filtered = vim.tbl_filter(function(p)
    local uses_sel = p.prompt:find("@selection", 1, true)
    return (is_visual and uses_sel) or (not is_visual and not uses_sel)
  end, prompts)

  vim.ui.select(filtered, {
    prompt = "Select prompt: ",
    format_item = function(item) return item.desc end,
  }, function(choice)
    if choice then apply(choice.prompt) end
  end)
end

return M
