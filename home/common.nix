{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ../modules/git.nix
    ../modules/fish.nix
    ../modules/tmux.nix
    ../modules/fzf.nix
    ../modules/lazygit.nix
    ../modules/neovim.nix
    ../modules/claude.nix
    ../modules/python.nix
    ../modules/jupyter.nix
    ../modules/scripts.nix
  ];

  home = {
    stateVersion = "26.11";

    sessionVariables = {
      TYPST_ROOT = "${config.home.homeDirectory}/work";
      UNISONLOCALHOSTNAME = "FixedHostname";
    };

    sessionPath = [ "${config.home.homeDirectory}/.local/bin" ];

    packages = with pkgs; [
      tree-sitter
      typst
      nodejs
      ghc
      cmake
      docker-client
      mosh
      tree
      unison
      wget
      ffmpeg
      imagemagick
      ghostscript
      poppler-utils # provides pdftotext
      timewarrior
      nh
      github-copilot-cli
    ];

    file = {
      ".clang-format".source = ../config/clang/clang-format;
      ".vimrc".source = ../config/vim/vimrc;
    };

    # ~/.hushlogin must be a real empty file rather than a store symlink so
    # login services can read it directly.
    # - vim's undodir/backupdir (referenced from config/vim/vimrc) must exist
    #   before vim can write undo/backup files there. home.file only creates
    #   files, not empty dirs, so we mkdir here.
    activation.userHomeSetup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      : > "$HOME/.hushlogin"
      mkdir -p "$HOME/.vim/undodir" "$HOME/.vim/backups"
    '';
  };

  programs = {
    man.generateCaches = false;

    bat = {
      enable = true;
      config.theme = "Dracula";
    };

    fd.enable = true;

    eza = {
      enable = true;
      icons = "always";
      enableFishIntegration = true; # generates ls, ll, la, lt, lla aliases
    };

    zoxide = {
      enable = true;
      # Disabled: HM's implementation emits `zoxide init fish | source`, which
      # forks zoxide on every shell startup. On macOS with EDR that's ~6-9 ms.
      # home/darwin.nix sources a nix-built static init file instead.
      enableFishIntegration = false;
    };

    pandoc.enable = true;

    ripgrep.enable = true;
  };

  # Enable XDG on macOS so programs (lazygit, etc.) use ~/.config/ instead of
  # ~/Library/Application Support/. Many HM modules check config.xdg.enable
  # to decide the config path on Darwin.
  xdg.enable = true;

}
