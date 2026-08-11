local contexts = require("util.prompt").contexts
local CompletionItemKind = require("blink.cmp.types").CompletionItemKind

local source = {}

-- Items are static — build once
local cached_items
local function get_items()
  if cached_items then return cached_items end
  cached_items = {}
  local names = vim.tbl_keys(contexts)
  table.sort(names)
  for _, name in ipairs(names) do
    cached_items[#cached_items + 1] = {
      label = name,
      kind = CompletionItemKind.Variable,
      insertText = name,
    }
  end
  return cached_items
end

function source.new()
  return setmetatable({}, { __index = source })
end

function source:enabled()
  return vim.bo.filetype == "prompt"
end

function source:get_trigger_characters()
  return { "@" }
end

function source:get_completions(_, callback)
  callback({
    items = get_items(),
    is_incomplete_forward = false,
    is_incomplete_backward = false,
  })
end

return source
