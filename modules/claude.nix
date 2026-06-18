{ config, lib, ... }:

{
  programs.claude-code = {
    enable = true;
    context = lib.mkDefault ../config/claude/CLAUDE.md;
    settings = lib.mkDefault (import ../config/claude/settings.nix { inherit config; });
    skills = ../config/skills;
  };

  home.file.".claude/statusline.sh" = {
    source = ../config/claude/statusline.sh;
    executable = true;
  };
}
