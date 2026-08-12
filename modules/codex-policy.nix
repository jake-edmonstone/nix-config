{ pkgs, ... }:

let
  blockRm = pkgs.writeShellApplication {
    name = "codex-block-rm";
    runtimeInputs = [
      pkgs.gnugrep
      pkgs.jq
    ];
    text = ''
      command=$(jq -r '.tool_input.command // ""')

      if grep -Eq '(^|[[:space:];|&()])([^[:space:];|&()]*/)?rm([[:space:];|&()]|$)' <<< "$command"; then
        jq -n '{
          hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "deny",
            permissionDecisionReason: "Use `trash` instead of `rm` so deleted files remain recoverable."
          }
        }'
      fi
    '';
  };
  requirements = (pkgs.formats.toml { }).generate "codex-requirements.toml" {
    features.hooks = true;
    hooks = {
      managed_dir = "${blockRm}/bin";
      PreToolUse = [
        {
          matcher = "^Bash$";
          hooks = [
            {
              type = "command";
              command = "${blockRm}/bin/codex-block-rm";
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
