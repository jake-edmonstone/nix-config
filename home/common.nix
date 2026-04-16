{ config, pkgs, lib, isCerebras, ... }:

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
  ];

  home.stateVersion = "26.05";

  home.packages = with pkgs; [
    claude-code
    ripgrep
    fd
    tree-sitter
    typst
    nodejs
  ];

  # ── Programs with native modules ──────────────────────────────────────────

  programs.bat = {
    enable = true;
    config.theme = "Dracula";
  };

  programs.eza = {
    enable = true;
    enableZshIntegration = false; # we define our own aliases with --icons=always
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
    "sioyek/keys_user.config".source = ../config/sioyek/keys_user.config;
    "sioyek/prefs_user.config".source = ../config/sioyek/prefs_user.config;
    "git/ignore".source = ../dotfiles/git-ignore;
  };
}
