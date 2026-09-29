return {
  { "folke/persistence.nvim", enabled = false },
  { "folke/flash.nvim", enabled = false },
  {
    "nvim-treesitter/nvim-treesitter-context",
    opts = { max_lines = 0 }, -- values <= 0 disable the context-height limit
  },
  {
    "lewis6991/gitsigns.nvim",
    init = function()
      local function git_from_current_buffer(args)
        local name = vim.api.nvim_buf_get_name(0)
        if name == "" then
          vim.notify("Gitsigns needs a file in a Git repository", vim.log.levels.WARN)
          return nil
        end

        local result = vim.system(vim.list_extend({ "git", "-C", vim.fs.dirname(name) }, args), { text = true }):wait()
        if result.code ~= 0 then
          vim.notify(vim.trim(result.stderr), vim.log.levels.ERROR)
          return nil
        end
        return vim.trim(result.stdout)
      end

      vim.api.nvim_create_user_command("GitsignsMergeBase", function(command)
        local base_ref = command.args
        if base_ref == "" then
          base_ref = git_from_current_buffer({ "symbolic-ref", "--quiet", "refs/remotes/origin/HEAD" })
        end
        if not base_ref or base_ref == "" then
          vim.notify("Could not resolve origin/HEAD for this repository", vim.log.levels.ERROR)
          return
        end

        local merge_base = git_from_current_buffer({ "merge-base", "HEAD", base_ref })
        if merge_base and merge_base ~= "" then
          require("gitsigns").change_base(merge_base, true)
          vim.notify("Gitsigns base set to the merge-base with " .. base_ref)
        end
      end, {
        nargs = "?",
        desc = "Compare Gitsigns against the merge-base with a revision (default: origin/HEAD)",
      })

      vim.api.nvim_create_user_command("GitsignsResetBase", function()
        require("gitsigns").reset_base(true)
        vim.notify("Gitsigns base reset to the index")
      end, { desc = "Reset Gitsigns to compare against the index" })
    end,
  },

  {
    "nvim-mini/mini.ai",
    opts = {
      mappings = {
        around_next = "", -- free an for builtin treesitter node selection
        inside_next = "", -- free in for builtin treesitter node selection
      },
    },
  },

  {
    "folke/noice.nvim",
    opts = { presets = { lsp_doc_border = true } },
  },

  {
    "folke/snacks.nvim",
    opts = {
      explorer = { enabled = false },
      -- Inline image rendering (PDF / LaTeX / Mermaid / raster) via Kitty
      -- graphics. `needs_setup = true` in Snacks.image, so this opt-in is
      -- required. Render dependencies are managed by Nix; magick and gs remain
      -- global CLIs, while tectonic and mmdc are on Neovim's wrapper PATH.
      image = { enabled = true },
      styles = {
        win = { border = "rounded" },
        news = { border = "rounded" },
        lazygit = { border = "rounded" },
      },
      picker = {
        win = { preview = { wo = { wrap = true } } },
        sources = {
          files = { hidden = true },
          explorer = { layout = { layout = { position = "right" } } },
        },
        layout = { preset = "default" },
        hidden = true,
      },
    },
  },

  {
    "pwntester/octo.nvim",
    opts = { use_local_fs = true },
  },

  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      opts.options.component_separators = { left = "", right = "" } -- pipe separator character: │
      opts.options.section_separators = ""
      opts.sections.lualine_c = {
        { "diagnostics" },
        { "filetype", icon_only = true, separator = "", padding = { left = 1, right = 0 } },
        { LazyVim.lualine.pretty_path({ modified_sign = " ●", modified_hl = "LualineModified" }) },
      }
      table.insert(opts.sections.lualine_x, { "lsp_status" })
      opts.sections.lualine_z = {}
    end,
  },

  {
    "nvim-mini/mini.diff",
    event = "LazyFile",
    opts = {
      mappings = {
        apply = "",
        reset = "",
        textobject = "",
        goto_first = "",
        goto_prev = "",
        goto_next = "",
        goto_last = "",
      },
      view = {
        style = "sign",
        -- Keep mini.diff active for overlay only; let gitsigns own gutter visuals.
        signs = { add = " ", change = " ", delete = " " },
        priority = 1,
      },
    },
    keys = {
      {
        "<leader>go",
        function()
          require("mini.diff").toggle_overlay(0)
        end,
        desc = "Toggle mini.diff overlay",
      },
    },
  },

  {
    "christoomey/vim-tmux-navigator",
    init = function()
      -- Own the mappings below so the plugin's default <C-l> mapping cannot
      -- replace the native-multicursor-aware version.
      vim.g.tmux_navigator_no_mappings = 1
    end,
    cmd = {
      "TmuxNavigateLeft",
      "TmuxNavigateDown",
      "TmuxNavigateUp",
      "TmuxNavigateRight",
      "TmuxNavigatePrevious",
      "TmuxNavigatorProcessList",
    },
    keys = {
      {
        "<c-h>",
        function()
          vim.cmd("TmuxNavigateLeft")
        end,
        desc = "Navigate left (tmux)",
      },
      {
        "<c-j>",
        function()
          vim.cmd("TmuxNavigateDown")
        end,
        desc = "Navigate down (tmux)",
      },
      {
        "<c-k>",
        function()
          vim.cmd("TmuxNavigateUp")
        end,
        desc = "Navigate up (tmux)",
      },
      {
        "<c-l>",
        function()
          local multicursor = vim.api.nvim_create_namespace("nvim.multicursor")
          local cursors = vim.api.nvim_buf_get_extmarks(0, multicursor, 0, -1, { limit = 1 })
          if #cursors > 0 then
            vim.api.nvim_buf_clear_namespace(0, multicursor, 0, -1)
          else
            vim.cmd("TmuxNavigateRight")
          end
        end,
        desc = "Clear multicursors / navigate right (tmux)",
      },
      { "<c-\\>", "<cmd><C-U>TmuxNavigatePrevious<cr>", desc = "Navigate previous (tmux)" },
    },
  },
}
