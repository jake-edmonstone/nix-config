{ pkgs, ... }:

{
  programs.ghostty = {
    enable = true;
    package = pkgs.ghostty-bin; # pkgs.ghostty (source build) is broken on darwin
    enableZshIntegration = false;

    settings = {
      font-family = "Maple Mono NF";
      font-size = 18;
      font-feature = [ "cv01" ];
      theme = "Dracula";
      cursor-style-blink = true;
      cursor-text = "#000000";
      custom-shader = "shaders/cursor_smear.glsl";
      background-opacity = 0.9;
      background-blur = true;
      mouse-hide-while-typing = true;
      macos-titlebar-style = "hidden";
      macos-option-as-alt = true;
      # no-title: tmux already sets the window title from session name.
      # no-sudo: we rarely invoke sudo interactively and the wrapper adds a hook.
      # no-cursor: we set our own cursor style via cursor-style-blink.
      # OSC 133 prompt marks stay on — they're core, not a toggle.
      shell-integration-features = "no-cursor,no-sudo,no-title";
      confirm-close-surface = false;
      bell-features = "attention";
      # Disable Sparkle auto-update machinery: the app is nix-managed, so
      # Sparkle-driven updates would clash. Also stops the recurring "Check
      # for updates automatically?" prompt on launch (ghostty#9571).
      auto-update = "off";
    };
  };

  xdg.configFile."ghostty/shaders/cursor_smear.glsl".source =
    ../config/ghostty/shaders/cursor_smear.glsl;
}
