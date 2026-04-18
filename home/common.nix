{ config, lib, pkgs, isCerebras, ... }:

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

  # Install the home-manager CLI so `home-manager switch` and the `rebuild`
  # function work after the first activation on standalone (Linux) setups.
  # On nix-darwin this is provided by `darwin-rebuild`, but Linux needs
  # explicit opt-in.
  programs.home-manager.enable = true;

  # On standalone Linux (Cerebras), home-manager needs explicit opt-in to set
  # up PATH to include ~/.nix-profile/bin. Without this, tools installed via
  # home.packages (home-manager, nvim, ripgrep, claude-code, …) aren't on PATH
  # inside the chroot-spawned zsh. nix-darwin handles the equivalent on Mac.
  targets.genericLinux.enable = pkgs.stdenv.isLinux;

  home.sessionVariables = {
    DOTFILES = "${config.home.homeDirectory}/dotfiles-nix";
    TYPST_ROOT = "${config.home.homeDirectory}/typst";
    UNISONLOCALHOSTNAME = "FixedHostname";
  };

  home.sessionPath = [
    "${config.home.homeDirectory}/.local/share/nvim/mason/bin"
    "${config.home.homeDirectory}/.local/bin"
  ] ++ lib.optionals pkgs.stdenv.isLinux [
    # Standalone home-manager on Linux: no nix-darwin / NixOS module to set
    # this up automatically, so add the user nix profile explicitly.
    "${config.home.profileDirectory}/bin"
  ];

  # Enable XDG on macOS so programs (lazygit, etc.) use ~/.config/ instead of
  # ~/Library/Application Support/. Many HM modules check config.xdg.enable
  # to decide the config path on Darwin.
  xdg.enable = true;

  home.packages = with pkgs; [
    ripgrep
    fd
    tree-sitter
    trash-cli
    cpulimit
    claude-code # from sadjow/claude-code-nix overlay — tracks upstream hourly
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
  ] ++ lib.optionals pkgs.stdenv.isLinux [
    xclip # tmux copy-mode on Linux pipes to xclip; Rocky 9 doesn't ship it
  ];

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

  home.file = {
    ".clang-format".source = ../dotfiles/clang-format;
    ".vimrc".source = ../dotfiles/vimrc;
    ".p10k.zsh".source = ../dotfiles/p10k.zsh;
    # Ensure vim directories exist
    ".vim/undodir/.keep".text = "";
    ".vim/backups/.keep".text = "";
  };

  # ~/.hushlogin must be a REAL empty file (not a /nix/store symlink). On
  # rootless Nix, /nix/store isn't mounted during the SSH login stage — sshd
  # and PAM check for .hushlogin BEFORE nix-user-chroot is entered, so a
  # symlink into the store dangles and hushlogin silently fails to suppress
  # the MOTD / "Last login" banner.
  home.activation.writeHushlogin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    : > "$HOME/.hushlogin"
  '';

  xdg.configFile = {
    "git/ignore".source = ../dotfiles/gitignore;
  };
}
