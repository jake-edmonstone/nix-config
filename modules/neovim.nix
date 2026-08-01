{
  config,
  pkgs,
  ...
}:

{
  programs.neovim = {
    enable = true;
    defaultEditor = true;

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
    # clangd comes from Apple's toolchain, and project environments provide
    # clang-format; nixpkgs clang-tools is intentionally kept off this PATH to
    # avoid conflicting with the Apple toolchain.
    extraPackages = with pkgs; [
      tree-sitter
      lua-language-server
      stylua
      pyright
      ruff
      shfmt
      tinymist
      haskell-language-server
      websocat
      typstyle # conform.nvim formatter for typst (LazyVim typst extra)
      tectonic # modern LaTeX engine (~80 MB vs texlive's ~4 GB)
      mermaid-cli # mmdc — Mermaid diagrams
      vscode-langservers-extracted # json/html/css/eslint LSPs (unrelated to VSCode at runtime)
      # LazyVim lang.nix extra expects all three: nil_ls (LSP), nixfmt (formatter
      # via conform.nvim), statix (linter via nvim-lint). flake's `nix fmt` uses
      # nixfmt-tree which wraps the same nixfmt binary, so output is identical.
      nil
      nixfmt
      statix
    ];

  };

  # Deploy entire nvim config as a mutable symlink (instant edits, lazy.nvim can write lockfile)
  xdg.configFile."nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/config/nvim";
}
