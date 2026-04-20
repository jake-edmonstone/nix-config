{ config, pkgs, ... }:

{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    # withRuby/withPython3 default to false at home.stateVersion >= 26.05

    # Keep ~/.config/nvim fully owned by our own repo. Without this,
    # programs.neovim writes an init.lua (provider disables) into
    # .config/nvim/init.lua, which collides with our whole-dir symlink.
    # sideloadInitLua = true skips writing init.lua and passes the same
    # content via `--cmd 'lua dofile(...)'` (additive, doesn't shadow ours).
    sideloadInitLua = true;

    # LSP servers + formatters, declared declaratively instead of mason.
    # Mason re-installs these into ~/.local/share/nvim/mason/bin at runtime,
    # hooks lspconfig on BufReadPre (~15-22 ms), and creates a supplementary
    # PATH. Managing them via nix puts them on nvim's wrapper PATH directly
    # and lets the mason plugins be disabled (see config/nvim/lua/plugins/lang.lua).
    # clangd is provided by clang-tools in home/common.nix; on Cerebras the user
    # has an explicit clangd path override in config/nvim/lua/plugins/lang.lua.
    extraPackages = with pkgs; [
      lua-language-server
      stylua
      pyright
      ruff
      shfmt
      tinymist
      typstyle                      # conform.nvim formatter for typst (LazyVim typst extra)
      vscode-langservers-extracted  # json/html/css/eslint LSPs (unrelated to VSCode at runtime)
    ];
  };

  # Deploy entire nvim config as a mutable symlink (instant edits, lazy.nvim can write lockfile)
  xdg.configFile."nvim".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/nix-config/config/nvim";
}
