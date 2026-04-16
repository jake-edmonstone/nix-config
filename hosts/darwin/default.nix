{ pkgs, ... }:

{
  system.primaryUser = "jbedm";
  system.stateVersion = 6;
  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.allowUnfree = true;

  users.users.jbedm.home = "/Users/jbedm";

  # Nix daemon and settings are managed by the Determinate Nix package.
  # nix-darwin's nix.* options are disabled to avoid conflicts.
  nix.enable = false;

  security.pam.services.sudo_local.touchIdAuth = true;

  programs.zsh.enable = true;

  fonts.packages = with pkgs; [
    maple-mono.NF
    newcomputermodern   # full family (Book weight) for Typst documents
  ];

  # ---------------------------------------------------------------------------
  # Homebrew (GUI apps only — CLI tools are in nixpkgs)
  # ---------------------------------------------------------------------------
  nix-homebrew = {
    enable = true;
    user = "jbedm";
  };

  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      upgrade = true;
      cleanup = "zap";
    };
    casks = [
      "hammerspoon"
      "raycast"
      "spotify"
      "stats"
    ];
    # masApps requires being signed into the App Store first.
    # Install Goodnotes manually: mas install 1444383602
    masApps = {};

  };

  # ---------------------------------------------------------------------------
  # macOS defaults
  # ---------------------------------------------------------------------------
  system.defaults = {
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
      "com.raycast.macos" = {
        useHyperKeyIcon = true;
        raycastShouldFollowSystemAppearance = true;
        raycast_hyperKey_state = {
          enabled = true;
          includeShiftKey = true;
          keyCode = 230;
        };
      };
    };
  };

  system.activationScripts.postActivation.text = ''
    /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
    killall Finder || true
    killall SystemUIServer || true
    killall Raycast || true
  '';
}
