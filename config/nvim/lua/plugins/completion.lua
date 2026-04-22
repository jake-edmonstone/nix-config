return {
  -- load custom lua-format snippets (the luasnip extra only loads vscode-format)
  {
    "L3MON4D3/LuaSnip",
    config = function(_, opts)
      require("luasnip").setup(opts)
      require("luasnip.loaders.from_lua").lazy_load({
        paths = { vim.fn.stdpath("config") .. "/snippets" },
      })
    end,
  },

  {
    "saghen/blink.cmp",
    opts = {
      cmdline = { enabled = false },
      sources = {
        default = {
          "lsp",
          "path",
          "snippets",
          "buffer",
        },
        per_filetype = {
          prompt = { "prompt_ctx" },
        },
        providers = {
          prompt_ctx = {
            module = "util.prompt.blink-source",
            name = "Prompt",
          },
        },
      },
      completion = {
        menu = { border = "none" },
        list = {
          selection = {
            preselect = false,
            auto_insert = false,
          },
        },
        ghost_text = { enabled = false },
      },
      keymap = {
        preset = "enter",
        ["<Tab>"] = {
          function(cmp)
            if cmp.snippet_active({ direction = 1 }) then
              return cmp.snippet_forward()
            end
            return cmp.accept({ index = 1 })
          end,
          "fallback",
        },
        ["<S-Tab>"] = {
          function(cmp)
            if cmp.snippet_active({ direction = -1 }) then
              return cmp.snippet_backward()
            end
          end,
          "fallback",
        },
      },
    },
  },
}
