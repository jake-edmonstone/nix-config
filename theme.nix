let
  mode = "dark"; # "light" or "dark"

  palettes = {
    dark = {
      name = "Dracula";
      background = "#282A36";
      currentLine = "#44475A";
      currentLineSolid = "#353747";
      selection = "#44475A";
      foreground = "#F8F8F2";
      comment = "#6272A4";
      red = "#FF5555";
      orange = "#FFB86C";
      yellow = "#F1FA8C";
      green = "#50FA7B";
      cyan = "#8BE9FD";
      purple = "#BD93F9";
      pink = "#FF79C6";
    };

    light = {
      name = "Catppuccin Latte";
      background = "#EFF1F5";
      currentLine = "#9CA0B0";
      currentLineSolid = "#E6E9EF";
      selection = "#CCD0DA";
      foreground = "#4C4F69";
      comment = "#7C7F93";
      red = "#D20F39";
      orange = "#FE640B";
      yellow = "#DF8E1D";
      green = "#40A02B";
      cyan = "#179299";
      purple = "#8839EF";
      pink = "#EA76CB";
    };
  };

  palette =
    if builtins.hasAttr mode palettes then
      builtins.getAttr mode palettes
    else
      throw "theme.nix: mode must be either \"dark\" or \"light\"";
in
{
  inherit mode palette palettes;
  isDark = mode == "dark";
  isLight = mode == "light";
  noHash = color: builtins.substring 1 6 color;
}
