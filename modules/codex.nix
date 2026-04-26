{ lib, pkgs, ... }:

let
  sharedAgents = import ../config/agents;
  tomlFormat = pkgs.formats.toml { };

  mkCodexAgent =
    name: a:
    let
      effort = a.codex.model_reasoning_effort or "high";
    in
    tomlFormat.generate "${name}.toml" {
      inherit name;
      inherit (a) description;
      model_reasoning_effort = effort;
      developer_instructions = builtins.readFile a.body;
    };

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
    # used by modules/claude.nix).
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

    # Keep Codex config fully declarative. This disables Codex writeback for
    # mutable preferences/trust state because the file is store-backed.
    ".codex/config.toml".text = ''
      model = "gpt-5.3-codex"
      model_reasoning_effort = "medium"
      approvals_reviewer = "user"
      sandbox_mode = "read-only"
      approval_policy = "untrusted"

      [notice]
      hide_gpt5_1_migration_prompt = true
      "hide_gpt-5.1-codex-max_migration_prompt" = true

      [notice.model_migrations]
      "gpt-5.3-codex" = "gpt-5.4"

      [plugins."github@openai-curated"]
      enabled = true

      [projects."/Users/jbedm/nix-config"]
      trust_level = "trusted"

      [projects."/Users/jbedm/typst"]
      trust_level = "trusted"

      [projects."/Users/jbedm/projects"]
      trust_level = "trusted"

      [projects."/Users/jbedm"]
      trust_level = "trusted"
    '';
  };
}
