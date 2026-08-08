{
  config,
  lib,
  pkgs,
  ...
}:

let
  theme = import ../theme.nix;
  rgb =
    if theme.isDark then
      {
        dir = "189;147;249";
        git = "255;121;198";
      }
    else
      {
        dir = "100;74;201";
        git = "163;20;77";
      };
in

{
  programs.claude-code = {
    enable = true;
    context = lib.mkDefault ../config/claude/CLAUDE.md;
    settings = lib.mkDefault (import ../config/claude/settings.nix { inherit config; });
  };

  home.file.".claude/statusline.sh" = {
    source = pkgs.replaceVars ../config/claude/statusline.sh {
      dirRgb = rgb.dir;
      gitRgb = rgb.git;
    };
    executable = true;
  };
}
