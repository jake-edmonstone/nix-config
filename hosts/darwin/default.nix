{
  config,
  lib,
  pkgs,
  ...
}:

let
  theme = import ../../theme.nix;
in

{
  imports = [ ../../modules/codex-policy.nix ];

  system = {
    primaryUser = "jbedm";
    # Compatibility pin for nix-darwin migrations, not the package release.
    stateVersion = 7;

    keyboard = {
      enableKeyMapping = true;
      # Right Option → F19, used as Hyper trigger by Hammerspoon (modal).
      userKeyMapping = [
        {
          HIDKeyboardModifierMappingSrc = 30064771129; # 0x700000039 caps lock
          HIDKeyboardModifierMappingDst = 30064771113; # 0x700000029 escape
        }
        {
          HIDKeyboardModifierMappingSrc = 1095216660483; # 0xFF00000003 fn
          HIDKeyboardModifierMappingDst = 30064771296; # 0x7000000E0 left control
        }
        {
          HIDKeyboardModifierMappingSrc = 30064771303; # 0x7000000E7 right command
          HIDKeyboardModifierMappingDst = 1095216660483; # 0xFF00000003 fn
        }
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
        autohide-delay = 0.0; # instant show on hover
        autohide-time-modifier = 0.0; # instant slide
        expose-animation-duration = 0.1; # faster mission control
        launchanim = false; # no bouncy app-launch animation
        mineffect = "scale"; # snappier than default "genie"
        mru-spaces = false;
        show-recents = true;
        tilesize = 64;
      };

      finder = {
        AppleShowAllFiles = true;
        FXDefaultSearchScope = "SCcf";
        FXEnableExtensionChangeWarning = false; # skip "are you sure?" on rename
        FXPreferredViewStyle = "clmv";
        NewWindowTarget = "Home"; # new Finder windows open at ~/
        ShowExternalHardDrivesOnDesktop = true;
        ShowHardDrivesOnDesktop = false;
        ShowPathbar = true;
        ShowRemovableMediaOnDesktop = true;
        ShowStatusBar = true;
      };

      NSGlobalDomain = {
        AppleInterfaceStyle = if theme.isDark then "Dark" else null;
        AppleShowAllExtensions = true;
        KeyRepeat = 2;
        InitialKeyRepeat = 15;
        ApplePressAndHoldEnabled = false; # disable diacritics popup, allow key repeat
        AppleIconAppearanceTheme = if theme.isDark then "RegularDark" else null;
        NSAutomaticCapitalizationEnabled = true;
        NSAutomaticPeriodSubstitutionEnabled = true;
        NSAutomaticQuoteSubstitutionEnabled = false;
        NSAutomaticSpellingCorrectionEnabled = false;
        NSAutomaticWindowAnimationsEnabled = false; # kill window zoom animation
        NSNavPanelExpandedStateForSaveMode = true;
        NSNavPanelExpandedStateForSaveMode2 = true;
        NSWindowResizeTime = 0.001; # near-instant window resize (default ~0.2s)
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

      trackpad = {
        Clicking = true;
        TrackpadThreeFingerDrag = true; # drag windows / select text with 3 fingers
      };

      controlcenter = {
        BatteryShowPercentage = true;
        Sound = true; # pin sound slider to menu bar
        NowPlaying = true; # pin now-playing to menu bar
      };

      screensaver = {
        askForPassword = true;
        askForPasswordDelay = 0; # lock immediately when screensaver kicks in
      };

      LaunchServices.LSQuarantine = false; # skip "app downloaded from the internet" nag

      SoftwareUpdate.AutomaticallyInstallMacOSUpdates = false; # no surprise macOS reboots

      CustomUserPreferences = {
        "com.apple.finder" = {
          ShowSidebar = true;
        };
      };
    };

    activationScripts.preActivation.text = lib.optionalString theme.isLight ''
      # A null nix-darwin default means "do not manage", so remove the
      # dark-only preferences before the normal defaults phase restarts Dock.
      _uid=$(id -u ${config.system.primaryUser})
      if [ -n "$_uid" ]; then
        launchctl asuser "$_uid" sudo --user=${config.system.primaryUser} -- \
          defaults delete NSGlobalDomain AppleInterfaceStyle || true
        launchctl asuser "$_uid" sudo --user=${config.system.primaryUser} -- \
          defaults delete NSGlobalDomain AppleIconAppearanceTheme || true
      fi
    '';

    activationScripts.postActivation.text = ''
      # macOS Sequoia/Tahoe reads `com.apple.mouse.tapBehavior` at per-host
      # (ByHost) scope for the "Tap to click" switch, but nix-darwin's
      # system.defaults.trackpad.Clicking only writes user-global keys
      # (ByHost not yet supported — nix-darwin issue #1721). Write it here
      # as the user (activation itself runs as root).
      _uid=$(id -u ${config.system.primaryUser})
      if [ -n "$_uid" ]; then
        launchctl asuser "$_uid" sudo --user=${config.system.primaryUser} -- \
          defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1 || true
        # AppleInterfaceStyle otherwise requires logout/login before the live
        # desktop adopts the persisted value.
        launchctl asuser "$_uid" sudo --user=${config.system.primaryUser} -- \
          /usr/bin/osascript -e \
            'tell application "System Events" to tell appearance preferences to set dark mode to ${
              if theme.isDark then "true" else "false"
            }' || true
        launchctl asuser "$_uid" sudo --user=${config.system.primaryUser} -- \
          /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u || true
      fi
    '';
  };

  # Configuration reference docs are available online and otherwise add
  # evaluation/build work to every system generation.
  documentation.enable = false;

  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.allowUnfree = true;

  users.users.jbedm = {
    home = "/Users/jbedm";
    shell = pkgs.fish;
  };

  # Determinate Nix handles the daemon; the module also auto-sets
  # nix.enable = false to avoid nix-darwin stepping on Determinate's config.
  determinateNix = {
    enable = true;
    determinateNixd.telemetry.sentry.endpoint = null;
  };

  security.pam.services.sudo_local = {
    touchIdAuth = true;
    reattach = true; # Touch ID works inside tmux via pam_reattach
  };

  environment.shells = [ pkgs.fish ];

  programs = {
    fish = {
      enable = true;
      useBabelfish = true;
    };
    # nix-darwin defaults zsh on; disable its system shell setup explicitly.
    zsh.enable = false;
  };

  fonts.packages = with pkgs; [
    maple-mono.NF
    newcomputermodern # full family (Book weight) for Typst documents
    font-awesome # FA icons for Typst resume/cv
  ];

  # Homebrew (GUI apps only — CLI tools are in nixpkgs)
  nix-homebrew = {
    enable = true;
    user = "jbedm";
    # Disabled: we set brew env in programs.fish.shellInit directly (inline
    # instead of eval'ing brew shellenv, saves ~100ms per shell).
    enableFishIntegration = false;
    enableZshIntegration = false;
  };

  homebrew = {
    enable = true;
    onActivation = {
      # TODO: nix-homebrew#131/#149 lose HOMEBREW_PATH when auto-update
      # re-executes brew, preventing Brew Bundle from finding mas.
      autoUpdate = false;
      upgrade = true;
      cleanup = "uninstall";
    };
    casks = [
      "chatgpt"
      "discord"
      "docker-desktop"
      "google-chrome"
      "hammerspoon"
      "helium-browser"
      "keyboardcleantool"
      "microsoft-teams"
      "nordvpn"
      "notion"
      "obsidian"
      "spotify"
      "tor-browser"
      "utm"
      # "xquartz"
      "zoom"
    ];
    masApps = {
      "CrystalFetch ISO Downloader" = 6454431289;
      "Goodnotes: AI Notes, Docs, PDF" = 1444383602;
      "HP Smart" = 1474276998;
      # "Microsoft Outlook" = 985367838;
      "Microsoft PowerPoint" = 462062816;
      "Microsoft Word" = 462054704;
      "uBlock Origin Lite" = 6745342698;
    };
  };
}
