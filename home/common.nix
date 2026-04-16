{ pkgs, isCerebras, ... }:

{
  imports = [
    ../modules/git.nix
    ../modules/zsh.nix
    ../modules/tmux.nix
    ../modules/fzf.nix
    ../modules/lazygit.nix
    ../modules/neovim.nix
    ../modules/claude.nix
    ../modules/scripts.nix
    ../modules/sioyek.nix
  ];

  home.stateVersion = "26.05";

  home.sessionVariables = {
    DOTFILES = "$HOME/dotfiles-nix";
    TYPST_ROOT = "$HOME/typst";
    UNISONLOCALHOSTNAME = "FixedHostname";
  };

  # Enable XDG on macOS so programs (lazygit, etc.) use ~/.config/ instead of
  # ~/Library/Application Support/. Many HM modules check config.xdg.enable
  # to decide the config path on Darwin.
  xdg.enable = true;

  home.packages = with pkgs; [
    ripgrep
    fd
    tree-sitter
    typst
    nodejs
    clang-tools # provides clang-format
    cmake
    docker-client
    mosh
    pandoc
    tree
    unison
    wget
  ];

  # ── Programs with native modules ──────────────────────────────────────────

  programs.bat = {
    enable = true;
    config.theme = "Dracula";
  };

  programs.eza = {
    enable = true;
    icons = "always";
    enableZshIntegration = true; # generates ls, ll, la, lt, lla aliases
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = !isCerebras;
  };

  # ── Dotfiles ──────────────────────────────────────────────────────────────

  home.file = {
    ".hushlogin".text = "";
    ".clang-format".source = ../dotfiles/clang-format;
    ".vimrc".source = ../dotfiles/vimrc;
    ".p10k.zsh".source = ../dotfiles/p10k.zsh;
    # Ensure vim directories exist
    ".vim/undodir/.keep".text = "";
    ".vim/backups/.keep".text = "";
  };

  # ── XDG config files ─────────────────────────────────────────────────────

  xdg.configFile = {
    "git/ignore".source = ../dotfiles/gitignore;
  };
}
