{
  config,
  ...
}:

let
  theme = import ../theme.nix;
  themeFile = palette: ''
    background = ${palette.background}
    foreground = ${palette.foreground}
    cursor-color = ${palette.foreground}
    cursor-text = ${palette.background}
    selection-background = ${palette.selection}
    selection-foreground = ${palette.foreground}
    palette = 0=${palette.background}
    palette = 1=${palette.red}
    palette = 2=${palette.green}
    palette = 3=${palette.yellow}
    palette = 4=${palette.purple}
    palette = 5=${palette.pink}
    palette = 6=${palette.cyan}
    palette = 7=${palette.foreground}
    palette = 8=${palette.comment}
    palette = 9=${palette.red}
    palette = 10=${palette.green}
    palette = 11=${palette.yellow}
    palette = 12=${palette.purple}
    palette = 13=${palette.pink}
    palette = 14=${palette.cyan}
    palette = 15=${palette.foreground}
  '';
in
{
  # Keep the beta and its server under the official app's updater.
  home.file.".local/bin/rex".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex";

  xdg.configFile."rex/init.lua".source = ../config/rex/init.lua;
  xdg.configFile."rex/themes/Dracula".text = themeFile theme.palettes.dark;
  xdg.configFile."rex/themes/Catppuccin Latte".text = themeFile theme.palettes.light;

  programs.fish.interactiveShellInit = ''
    if set -q REX_BIN_DIR; and test -n "$REX_BIN_DIR"
      fish_add_path --path --move "$REX_BIN_DIR"
    end
  '';

  targets.darwin.defaults."com.superlogical.rex" = {
    # Captured from Rex's preferences after selecting the material in its UI.
    "Workspace.interfaceStyle" = "blendTheme";
    "Workspace.paneDensity" = "compact";
    # Rex forces headers on when its sidebar is hidden; floats may ignore this.
    "Workspace.showsPaneHeaders" = false;
    "Workspace.terminalFontName" = "Maple Mono NF";
    "Workspace.terminalFontPointSize" = 18.0;
    "Workspace.terminalCellHeightPercent" = 8.0;
    "Workspace.terminalCursorStyleForced" = false;
    "Workspace.cursorShadersEnabled" = true;
    "Workspace.cursorShader" = "warp";
  };
}
