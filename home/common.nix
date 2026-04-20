{ config, lib, pkgs, isDarwin, isRootlessLinux, isCerebras, ... }:

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

  # On standalone rootless Linux, home-manager needs explicit opt-in to set
  # up PATH to include ~/.nix-profile/bin. Without this, tools installed via
  # home.packages (home-manager, nvim, ripgrep, claude-code, …) aren't on PATH
  # inside the chroot-spawned zsh. nix-darwin and NixOS handle the equivalent
  # automatically.
  targets.genericLinux.enable = isRootlessLinux;

  home.sessionVariables = {
    DOTFILES = "${config.home.homeDirectory}/dotfiles-nix";
    TYPST_ROOT = "${config.home.homeDirectory}/typst";
    UNISONLOCALHOSTNAME = "FixedHostname";
  };

  home.sessionPath = [
    "${config.home.homeDirectory}/.local/bin"
  ] ++ lib.optionals isRootlessLinux [
    # Standalone home-manager on rootless Linux: no nix-darwin / NixOS module
    # to set this up automatically, so add the user nix profile explicitly.
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
  ] ++ lib.optionals (isDarwin || isCerebras) [
    # sadjow/claude-code-nix overlay — tracks upstream hourly (Bun native).
    # Omitted on UW (nix-portable+proot): the Bun binary's TTY/raw-mode
    # syscalls deadlock under proot's ptrace interception; UW gets the
    # pinned pure-JS v2.1.112 via modules/claude-code-legacy.nix instead.
    pkgs.claude-code
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
    # Disabled: HM's implementation emits `eval "$(zoxide init zsh)"` which
    # forks zoxide on every shell startup. On macOS with EDR that's ~6-9 ms.
    # Mac sources a nix-built static init file in home/darwin.nix mkOrder 680.
    # On Cerebras the integration was already disabled.
    enableZshIntegration = false;
  };

  home.file = {
    ".clang-format".source = ../config/clang/clang-format;
    ".vimrc".source = ../dotfiles/vimrc;
    ".p10k.zsh".source = ../config/p10k/p10k.zsh;
  };

  # ~/.hushlogin must be a REAL empty file (not a /nix/store symlink). On
  # rootless Nix, /nix/store isn't mounted during the SSH login stage — sshd
  # and PAM check for .hushlogin BEFORE nix-user-chroot is entered, so a
  # symlink into the store dangles and hushlogin silently fails to suppress
  # the MOTD / "Last login" banner.
  home.activation.writeHushlogin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    : > "$HOME/.hushlogin"
  '';

  # vim's undodir and backupdir (referenced from dotfiles/vimrc) must exist
  # before vim can write undo/backup files there. home.file can only create
  # files, not empty dirs, so create these via an activation step.
  home.activation.mkVimDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.vim/undodir" "$HOME/.vim/backups"
  '';

  xdg.configFile = {
    "git/ignore".source = ../config/git/ignore;
  };
}
