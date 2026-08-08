let
  # Change this to "light" and rebuild to use Alucard everywhere.
  mode = "light";

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
      ansi = [
        "#21222C"
        "#FF5555"
        "#50FA7B"
        "#F1FA8C"
        "#BD93F9"
        "#FF79C6"
        "#8BE9FD"
        "#F8F8F2"
        "#6272A4"
        "#FF6E6E"
        "#69FF94"
        "#FFFFA5"
        "#D6ACFF"
        "#FF92DF"
        "#A4FFFF"
        "#FFFFFF"
      ];
    };

    light = {
      name = "Alucard";
      background = "#FFFBEB";
      currentLine = "#6C664B";
      currentLineSolid = "#E2DECA";
      selection = "#CFCFDE";
      foreground = "#1F1F1F";
      comment = "#6C664B";
      red = "#CB3A2A";
      orange = "#A34D14";
      yellow = "#846E15";
      green = "#14710A";
      cyan = "#036A96";
      purple = "#644AC9";
      pink = "#A3144D";
      ansi = [
        "#FFFBEB"
        "#CB3A2A"
        "#14710A"
        "#846E15"
        "#644AC9"
        "#A3144D"
        "#036A96"
        "#1F1F1F"
        "#6C664B"
        "#D74C3D"
        "#198D0C"
        "#9E841A"
        "#7862D0"
        "#BF185A"
        "#047FB4"
        "#2C2B31"
      ];
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
