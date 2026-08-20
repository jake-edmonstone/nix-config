{ pkgs, ... }:

let
  blockUnsafeDelete = pkgs.writeShellApplication {
    name = "codex-block-unsafe-delete";
    runtimeInputs = [
      pkgs.gnugrep
      pkgs.jq
    ];
    text = ''
      command=$(jq -r '.tool_input.command // ""')

      if grep -Eq '(^|[[:space:];|&()])([^[:space:];|&()]*/)?(rm|unlink)([[:space:];|&()]|$)' <<< "$command"; then
        jq -n '{
          hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "deny",
            permissionDecisionReason: "Use `trash` instead so deleted files remain recoverable."
          }
        }'
      fi
    '';
  };
  requirements = (pkgs.formats.toml { }).generate "codex-requirements.toml" {
    features.hooks = true;
    hooks = {
      managed_dir = "${blockUnsafeDelete}/bin";
      PreToolUse = [
        {
          matcher = "^Bash$";
          hooks = [
            {
              type = "command";
              command = "${blockUnsafeDelete}/bin/codex-block-unsafe-delete";
              timeout = 2;
            }
          ];
        }
      ];
    };
  };
in

{
  # Managed hooks are trusted by policy, avoiding writable trust state in the
  # declaratively generated ~/.codex/config.toml.
  environment.etc."codex/requirements.toml".source = requirements;
}
