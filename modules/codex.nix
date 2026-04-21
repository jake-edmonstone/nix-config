{ lib, pkgs, ... }:

let
  sharedAgents = import ../config/agents;

  mkCodexAgent =
    name: a:
    let
      effort = a.codex.model_reasoning_effort or "high";
      # Escape quotes and backslashes so a future description containing `"`
      # doesn't break the TOML parse.
      desc = lib.escape [ "\"" "\\" ] a.description;
    in
    pkgs.writeText "${name}.toml" ''
      name = "${name}"
      description = "${desc}"
      model_reasoning_effort = "${effort}"
      developer_instructions = """
      ${builtins.readFile a.body}"""
    '';

  agentsDir = pkgs.runCommand "codex-agents" { } ''
    mkdir -p $out
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: a: "cp ${mkCodexAgent name a} $out/${name}.toml") sharedAgents
    )}
  '';
in
{
  # codex from sadjow/codex-cli-nix overlay — tracks upstream hourly (same
  # pattern as claude-code). Native Rust binary; no Node.js runtime needed.
  home.packages = [ pkgs.codex ];

  home.file = {
    # Agents generated from the shared registry at config/agents/ (same source
    # used by modules/claude.nix). ~/.codex/config.toml is left unmanaged:
    # codex writes project trust levels there as you approve projects (same
    # reason we don't use programs.gh.settings for gh auth).
    ".codex/agents" = {
      source = agentsDir;
      recursive = true;
    };

    # Skills use a cross-tool SKILL.md format — same source directory as
    # modules/claude.nix points at for ~/.claude/skills.
    ".codex/skills" = {
      source = ../config/skills;
      recursive = true;
    };
  };
}
