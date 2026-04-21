{ config }:

{
  env = {
    CLAUDE_CODE_NO_FLICKER = "1";
    CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING = "1";
    MAX_THINKING_TOKENS = "63999";
    CLAUDE_CODE_EFFORT_LEVEL = "max";
  };
  permissions = {
    allow = [
      "Read"
      "Glob"
      "Grep"
      "WebFetch"
      "WebSearch"

      # File/dir inspection
      "Bash(ls *)"
      "Bash(find *)"
      "Bash(tree *)"
      "Bash(stat *)"
      "Bash(file *)"
      "Bash(realpath *)"
      "Bash(readlink *)"
      "Bash(basename *)"
      "Bash(dirname *)"

      # Content reading
      "Bash(cat *)"
      "Bash(head *)"
      "Bash(tail *)"
      "Bash(wc *)"
      "Bash(grep *)"
      "Bash(rg *)"

      # Navigation (cd between segments is common in compound commands)
      "Bash(cd *)"
      "Bash(pwd)"

      # System info
      "Bash(whoami)"
      "Bash(id)"
      "Bash(id *)"
      "Bash(hostname)"
      "Bash(hostname *)"
      "Bash(uname *)"
      "Bash(date)"
      "Bash(date *)"
      "Bash(uptime)"
      "Bash(groups)"
      "Bash(groups *)"

      # Environment / shell introspection
      "Bash(env)"
      "Bash(printenv *)"
      "Bash(which *)"
      "Bash(type *)"
      "Bash(command -v *)"
      "Bash(echo *)"

      # System state (read-only)
      "Bash(ps *)"
      "Bash(df *)"
      "Bash(du *)"

      # Text transform (output only)
      "Bash(diff *)"
      "Bash(sort *)"
      "Bash(uniq *)"
      "Bash(cut *)"
      "Bash(tr *)"
      "Bash(column *)"
      "Bash(jq *)"

      # Git (read-only) — space before * enforces a word boundary. Without the
      # space, `Bash(git status*)` would also match `git status-foo`.
      "Bash(git status *)"
      "Bash(git log *)"
      "Bash(git diff *)"
      "Bash(git branch *)"
      "Bash(git remote *)"
      "Bash(git rev-parse *)"
      "Bash(git show *)"
      "Bash(git blame *)"
      "Bash(git ls-files *)"
      "Bash(git ls-tree *)"
      "Bash(git ls-remote *)"
      "Bash(git describe *)"
      "Bash(git config --get *)"
      "Bash(git config --list *)"
      "Bash(git config -l *)"
      "Bash(git worktree list *)"
      "Bash(git stash list *)"
      "Bash(git stash show *)"
      "Bash(git tag --list *)"
      "Bash(git tag -l *)"

      # Nix (read-only)
      "Bash(nix eval *)"
      "Bash(nix flake show *)"
      "Bash(nix flake metadata *)"
      "Bash(nix flake check *)"
      "Bash(nix derivation show *)"
      "Bash(nix show-derivation *)"
      "Bash(nix search *)"
      "Bash(nix-instantiate --eval *)"
      "Bash(nix-instantiate --parse *)"

      # gh (read-only)
      "Bash(gh pr view *)"
      "Bash(gh pr list *)"
      "Bash(gh pr diff *)"
      "Bash(gh pr checks *)"
      "Bash(gh issue view *)"
      "Bash(gh issue list *)"
      "Bash(gh repo view *)"
      "Bash(gh run view *)"
      "Bash(gh run list *)"
    ];
    defaultMode = "default";
  };
  model = "opus[1m]";
  hooks = {
    Notification = [
      {
        matcher = "";
        hooks = [
          {
            type = "command";
            command = "printf '\\a'";
          }
        ];
      }
    ];
  };
  enabledPlugins = {
    "lua-lsp@claude-plugins-official" = true;
    "pyright-lsp@claude-plugins-official" = true;
  };
  # Non-official setting (accepted by Claude Code but not in the public docs) that
  # skips the first-time acknowledgment prompt shown when entering auto mode.
  # Referenced in upstream issues #33587 and #48066.
  skipAutoPermissionPrompt = true;
  statusLine = {
    type = "command";
    command = "bash ${config.home.homeDirectory}/.claude/statusline.sh";
  };
}
