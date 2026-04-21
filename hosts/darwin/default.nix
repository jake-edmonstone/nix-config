{ config, pkgs, ... }:

{
  system = {
    primaryUser = "jbedm";
    stateVersion = 6;

    keyboard = {
      enableKeyMapping = true;
      remapCapsLockToControl = true;
      # Right Option → F19, used as Hyper trigger by Hammerspoon (modal).
      userKeyMapping = [
        {
          HIDKeyboardModifierMappingSrc = 30064771302; # 0x7000000E6 right option
          HIDKeyboardModifierMappingDst = 30064771182; # 0x70000006E F19
        }
      ];
    };

    # macOS defaults
    defaults = {
      dock = {
        autohide = true;
        mru-spaces = false;
        show-recents = true;
        tilesize = 64;
      };

      finder = {
        AppleShowAllFiles = true;
        FXDefaultSearchScope = "SCcf";
        FXPreferredViewStyle = "clmv";
        ShowExternalHardDrivesOnDesktop = true;
        ShowHardDrivesOnDesktop = false;
        ShowPathbar = true;
        ShowRemovableMediaOnDesktop = true;
        ShowStatusBar = true;
      };

      NSGlobalDomain = {
        AppleInterfaceStyle = "Dark";
        AppleShowAllExtensions = true;
        KeyRepeat = 2;
        InitialKeyRepeat = 15;
        ApplePressAndHoldEnabled = false; # disable diacritics popup, allow key repeat
        AppleIconAppearanceTheme = "RegularDark"; # dark app icons
        NSAutomaticCapitalizationEnabled = true;
        NSAutomaticPeriodSubstitutionEnabled = true;
        NSAutomaticQuoteSubstitutionEnabled = false;
        NSAutomaticSpellingCorrectionEnabled = false;
        NSNavPanelExpandedStateForSaveMode = true;
        NSNavPanelExpandedStateForSaveMode2 = true;
      };

      screencapture = {
        disable-shadow = true;
        location = "~/Desktop";
        type = "png";
      };

      WindowManager = {
        EnableTiledWindowMargins = false;
        EnableTilingByEdgeDrag = true;
        EnableTilingOptionAccelerator = false;
        EnableTopTilingByEdgeDrag = true;
        HideDesktop = true;
        StageManagerHideWidgets = false;
        StandardHideWidgets = false;
      };

      trackpad.Clicking = true;

      CustomUserPreferences = {
        "com.apple.finder" = {
          ShowSidebar = true;
        };
      };
    };

    activationScripts.postActivation.text = ''
      /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
      killall Finder || true
      killall SystemUIServer || true

      # macOS Sequoia/Tahoe reads `com.apple.mouse.tapBehavior` at per-host
      # (ByHost) scope for the "Tap to click" switch, but nix-darwin's
      # system.defaults.trackpad.Clicking only writes user-global keys
      # (ByHost not yet supported — nix-darwin issue #1721). Write it here
      # as the user (activation itself runs as root).
      _uid=$(id -u ${config.system.primaryUser})
      if [ -n "$_uid" ]; then
        launchctl asuser "$_uid" sudo --user=${config.system.primaryUser} -- \
          defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1 || true
        launchctl asuser "$_uid" sudo --user=${config.system.primaryUser} -- \
          /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u || true
      fi
    '';
  };

  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.allowUnfree = true;

  users.users.jbedm.home = "/Users/jbedm";

  # Determinate Nix handles the daemon; the module also auto-sets
  # nix.enable = false to avoid nix-darwin stepping on Determinate's config.
  determinateNix.enable = true;

  security.pam.services.sudo_local = {
    touchIdAuth = true;
    reattach = true; # Touch ID works inside tmux via pam_reattach
  };

  # Trim system /etc/zshrc to the minimum we actually use. The defaults add
  # ~100-250ms of startup: a duplicate compinit (our user zshrc runs another
  # one with the right fpath), a `prompt suse` setup we override with p10k,
  # and bashcompinit which we don't use with Nix tools.
  programs.zsh = {
    enable = true;
    enableGlobalCompInit = false;
    enableBashCompletion = false;
    promptInit = "";
    # Inline `brew shellenv` output so we skip the ~100ms Ruby fork per shell.
    # nix-homebrew.enableZshIntegration is disabled below to prevent duplication.
    interactiveShellInit = ''
      export HOMEBREW_PREFIX="/opt/homebrew"
      export HOMEBREW_CELLAR="/opt/homebrew/Cellar"
      export HOMEBREW_REPOSITORY="/opt/homebrew"
      fpath[1,0]="/opt/homebrew/share/zsh/site-functions"
      export PATH="/opt/homebrew/bin:/opt/homebrew/sbin''${PATH+:$PATH}"
      [ -z "''${MANPATH-}" ] || export MANPATH=":''${MANPATH#:}"
      export INFOPATH="/opt/homebrew/share/info:''${INFOPATH:-}"
    '';
  };

  fonts.packages = with pkgs; [
    maple-mono.NF
    newcomputermodern # full family (Book weight) for Typst documents
  ];

  # Homebrew (GUI apps only — CLI tools are in nixpkgs)
  nix-homebrew = {
    enable = true;
    user = "jbedm";
    # Disabled: we set brew env in programs.zsh.interactiveShellInit directly
    # (inline instead of eval'ing brew shellenv, saves ~100ms per shell).
    enableZshIntegration = false;
  };

  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      upgrade = true;
      cleanup = "uninstall";
    };
    casks = [
      "docker-desktop"
      "hammerspoon"
      "keyboardcleantool"
      "obsidian"
      "orion"
      "spotify"
      "stats"
    ];
    # masApps requires being signed into the App Store first.
    # Install Goodnotes manually: mas install 1444383602
    masApps = { };
  };
}
