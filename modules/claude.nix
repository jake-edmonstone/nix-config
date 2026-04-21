{
  config,
  lib,
  pkgs,
  ...
}:

let
  sharedAgents = import ../config/agents;

  mkClaudeAgent =
    name: a:
    let
      model = a.claude.model or "opus";
      skills = a.claude.skills or [ ];
      skillsLines = lib.concatMapStringsSep "\n" (s: "  - ${s}") skills;
      skillsBlock = if skills == [ ] then "" else "skills:\n${skillsLines}\n";
    in
    pkgs.writeText "${name}.md" ''
      ---
      name: ${name}
      description: ${a.description}
      tools: ${a.claude.tools}
      model: ${model}
      ${skillsBlock}---

      ${builtins.readFile a.body}'';

  agentsDir = pkgs.runCommand "claude-agents" { } ''
    mkdir -p $out
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: a: "cp ${mkClaudeAgent name a} $out/${name}.md") sharedAgents
    )}
  '';
in
{
  home.file = {
    # mkDefault on the base .text values so per-host files (e.g. Cerebras)
    # can override with a plain assignment instead of lib.mkForce.
    ".claude/CLAUDE.md".text = lib.mkDefault (builtins.readFile ../config/claude/CLAUDE.md);

    ".claude/settings.json".text = lib.mkDefault (
      builtins.toJSON (import ../config/claude/settings.nix { inherit config; })
    );

    ".claude/statusline.sh" = {
      source = ../config/claude/statusline.sh;
      executable = true;
    };

    # Agents generated from the shared registry at config/agents/.
    # Add a new agent by dropping the body in config/agents/<name>.md and
    # adding an entry to config/agents/default.nix.
    ".claude/agents" = {
      source = agentsDir;
      recursive = true;
    };

    # Skills use a cross-tool format (SKILL.md with YAML frontmatter) that is
    # source-compatible between Claude Code, Codex CLI, Cursor, Gemini CLI, and
    # others. Both modules point at the same shared directory.
    ".claude/skills" = {
      source = ../config/skills;
      recursive = true;
    };
  };
}
