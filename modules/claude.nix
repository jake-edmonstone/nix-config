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
        dir = "136;57;239";
        git = "234;118;203";
      };
in

{
  # Claude's LSP plugins need these on its PATH, independently of Neovim's
  # wrapper-local dependencies. Nix shares the same package store paths.
  home.packages = with pkgs; [
    lua-language-server
    pyright
  ];

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
