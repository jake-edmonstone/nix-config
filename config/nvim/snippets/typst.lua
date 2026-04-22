local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local d = ls.dynamic_node
local sn = ls.snippet_node

-- build m×n grid of rows, each row wrapped in parens on its own line
local function grid_mn(rows, cols)
  local nodes = {}
  for r = 1, rows do
    local cells = {}
    for _ = 1, cols do
      cells[#cells + 1] = "$$"
    end
    local line = "  (" .. table.concat(cells, ", ") .. "),"
    if r < rows then
      nodes[#nodes + 1] = t({ line, "" })
    else
      nodes[#nodes + 1] = t({ line })
    end
  end
  return sn(nil, nodes)
end

ls.add_snippets("typst", {
  -- preamble snippet
  s("pre", {
    t('#import "preamble.typ" : *'),
    t({ "", "#show: preamble" }),
  }),

  -- my-table: mytable7x3 → 7 rows, 3 cols
  s({ trig = "mytable(%d+)x(%d+)", trigEngine = "pattern" }, {
    t("#my-table(("),
    t({ "", "" }),
    d(1, function(_, snip)
      local rows = tonumber(snip.captures[1]) or 3
      local cols = tonumber(snip.captures[2]) or 3
      return grid_mn(rows, cols)
    end),
    t({ "", "))" }),
  }),
})
