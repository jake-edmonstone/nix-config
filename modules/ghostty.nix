{ pkgs, ... }:

{
  programs.ghostty = {
    enable = true;
    package = pkgs.ghostty-bin; # pkgs.ghostty (source build) is broken on darwin
    enableZshIntegration = true;

    settings = {
      font-family = "Maple Mono NF";
      font-size = 18;
      theme = "Dracula";
      cursor-style-blink = true;
      cursor-text = "#000000";
      custom-shader = "shaders/cursor_smear.glsl";
      background-opacity = 0.9;
      background-blur = true;
      mouse-hide-while-typing = true;
      macos-titlebar-style = "hidden";
      macos-option-as-alt = true;
      shell-integration-features = "no-cursor,sudo,title";
      confirm-close-surface = false;
      bell-features = "attention";
    };
  };

  xdg.configFile."ghostty/shaders/cursor_smear.glsl".source = ../config/ghostty/shaders/cursor_smear.glsl;
}
