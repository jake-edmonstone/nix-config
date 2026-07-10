{
  config,
  lib,
  pkgs,
  isDarwin,
  isRootlessLinux,
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
      DOTFILES = "${config.home.homeDirectory}/nix-config";
      NH_FLAKE = "${config.home.homeDirectory}/nix-config";
      NH_HOME_FLAKE = "${config.home.homeDirectory}/nix-config";
      NH_DARWIN_FLAKE = "${config.home.homeDirectory}/nix-config";
      NH_OS_FLAKE = "${config.home.homeDirectory}/nix-config";
      TYPST_ROOT = "${config.home.homeDirectory}/work";
      UNISONLOCALHOSTNAME = "FixedHostname";
    }
    // lib.optionalAttrs isDarwin {
      # Typst font wiring only applies on macOS (where nix-darwin's fonts.packages
      # copies into /Library/Fonts/Nix Fonts). On Linux, a non-existent path would
      # silently point at nothing AND we'd have disabled the host's system fonts.
      TYPST_IGNORE_SYSTEM_FONTS = "true";
      TYPST_FONT_PATHS = "/Library/Fonts/Nix Fonts";
    };

    sessionPath = [
      "${config.home.homeDirectory}/.local/bin"
    ]
    ++ lib.optionals isRootlessLinux [
      # Standalone home-manager on rootless Linux: no nix-darwin / NixOS module
      # to set this up automatically, so add the user nix profile explicitly.
      "${config.home.profileDirectory}/bin"
    ];

    packages =
      (with pkgs; [
        tree-sitter
        trash-cli
        cpulimit
        typst
        nodejs
        cmake
        docker-client
        mosh
        tree
        unison
        wget
        imagemagick
        ghostscript
        poppler-utils # provides pdftotext
        gnused # GNU sed; fixes fish completions that assume GNU sed on macOS
        timewarrior
        nh
        github-copilot-cli
      ])
      ++ lib.optionals (!isDarwin) [
        pkgs.clang-tools # provides clangd and clang-format
      ];

    file = {
      ".clang-format".source = ../config/clang/clang-format;
      ".vimrc".source = ../config/vim/vimrc;
    };

    # - ~/.hushlogin must be a REAL empty file (not a /nix/store symlink). On
    #   rootless Nix, /nix/store isn't mounted during the SSH login stage — sshd
    #   and PAM check for .hushlogin BEFORE nix-user-chroot is entered, so a
    #   symlink into the store dangles and hushlogin silently fails to suppress
    #   the MOTD / "Last login" banner.
    # - vim's undodir/backupdir (referenced from config/vim/vimrc) must exist
    #   before vim can write undo/backup files there. home.file only creates
    #   files, not empty dirs, so we mkdir here.
    activation.userHomeSetup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      : > "$HOME/.hushlogin"
      mkdir -p "$HOME/.vim/undodir" "$HOME/.vim/backups"
    '';
  };

  programs = {
    # Install the home-manager CLI so `home-manager switch` and the `rebuild`
    # function work after the first activation on standalone (Linux) setups.
    # On nix-darwin this is provided by `darwin-rebuild`, but Linux needs
    # explicit opt-in.
    home-manager.enable = true;

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
      # Mac sources a nix-built static init file in home/darwin.nix.
      # On Cerebras the integration was already disabled.
      enableFishIntegration = false;
    };

    pandoc.enable = true;

    ripgrep.enable = true;
  };

  # On standalone rootless Linux, home-manager needs explicit opt-in to set
  # up PATH to include ~/.nix-profile/bin. Without this, tools installed by
  # Home Manager modules and home.packages aren't on PATH
  # inside the chroot-spawned fish. nix-darwin and NixOS handle the equivalent
  # automatically.
  targets.genericLinux.enable = isRootlessLinux;

  # Enable XDG on macOS so programs (lazygit, etc.) use ~/.config/ instead of
  # ~/Library/Application Support/. Many HM modules check config.xdg.enable
  # to decide the config path on Darwin.
  xdg.enable = true;

}
