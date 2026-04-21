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
    ../modules/zsh.nix
    ../modules/tmux.nix
    ../modules/fzf.nix
    ../modules/lazygit.nix
    ../modules/neovim.nix
    ../modules/claude.nix
    ../modules/scripts.nix
  ];

  home = {
    stateVersion = "26.05";

    sessionVariables = {
      DOTFILES = "${config.home.homeDirectory}/nix-config";
      TYPST_ROOT = "${config.home.homeDirectory}/typst";
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

    packages = with pkgs; [
      ripgrep
      fd
      # Tree-sitter CLI v0.26.8 from the prebuilt upstream release — replaces
      # nixpkgs's tree-sitter (still on 0.25.10) in this home-manager profile.
      # We can't do this via an nixpkgs overlay because neovim-unwrapped's
      # nixpkgs build calls `tree-sitter.buildGrammar` on its tree-sitter
      # input to compile the bundled grammar .so files, and our prebuilt
      # binary doesn't provide that function attribute. The nixpkgs 0.25.10
      # stays in neovim's build closure (never on user PATH); this 0.26.8 is
      # what nvim-treesitter's main-branch health check (requires >= 0.26.1)
      # sees at runtime.
      (callPackage ../pkgs/tree-sitter-cli-prebuilt.nix { })
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
      claude-code
    ];

    file = {
      ".clang-format".source = ../config/clang/clang-format;
      ".vimrc".source = ../config/vim/vimrc;
      ".p10k.zsh".source = ../config/p10k/p10k.zsh;
    };

    # ~/.hushlogin must be a REAL empty file (not a /nix/store symlink). On
    # rootless Nix, /nix/store isn't mounted during the SSH login stage — sshd
    # and PAM check for .hushlogin BEFORE nix-user-chroot is entered, so a
    # symlink into the store dangles and hushlogin silently fails to suppress
    # the MOTD / "Last login" banner.
    activation.writeHushlogin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      : > "$HOME/.hushlogin"
    '';

    # vim's undodir and backupdir (referenced from config/vim/vimrc) must exist
    # before vim can write undo/backup files there. home.file can only create
    # files, not empty dirs, so create these via an activation step.
    activation.mkVimDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p "$HOME/.vim/undodir" "$HOME/.vim/backups"
    '';
  };

  programs = {
    # Install the home-manager CLI so `home-manager switch` and the `rebuild`
    # function work after the first activation on standalone (Linux) setups.
    # On nix-darwin this is provided by `darwin-rebuild`, but Linux needs
    # explicit opt-in.
    home-manager.enable = true;

    bat = {
      enable = true;
      config.theme = "Dracula";
    };

    eza = {
      enable = true;
      icons = "always";
      enableZshIntegration = true; # generates ls, ll, la, lt, lla aliases
    };

    zoxide = {
      enable = true;
      # Disabled: HM's implementation emits `eval "$(zoxide init zsh)"` which
      # forks zoxide on every shell startup. On macOS with EDR that's ~6-9 ms.
      # Mac sources a nix-built static init file in home/darwin.nix mkOrder 680.
      # On Cerebras the integration was already disabled.
      enableZshIntegration = false;
    };
  };

  # On standalone rootless Linux, home-manager needs explicit opt-in to set
  # up PATH to include ~/.nix-profile/bin. Without this, tools installed via
  # home.packages (home-manager, nvim, ripgrep, claude-code, …) aren't on PATH
  # inside the chroot-spawned zsh. nix-darwin and NixOS handle the equivalent
  # automatically.
  targets.genericLinux.enable = isRootlessLinux;

  # Enable XDG on macOS so programs (lazygit, etc.) use ~/.config/ instead of
  # ~/Library/Application Support/. Many HM modules check config.xdg.enable
  # to decide the config path on Darwin.
  xdg.enable = true;
}
