{ config, lib, isCerebras, ... }:

{
  programs.git = {
    enable = true;

    settings = lib.mkMerge [
      {
        user = {
          name = if isCerebras then "Jake Edmonstone" else "jake-edmonstone";
          email = if isCerebras then "jake.edmonstone@cerebras.net" else "jbedmonstone@gmail.com";
        };
        core = {
          editor = "nvim";
          fsmonitor = false; # conflicts with gitstatusd (p10k), causes stale prompt
          untrackedCache = true;
        };
        pull.rebase = true;
        merge.conflictstyle = "zdiff3";
        rebase = {
          autostash = true;
          updateRefs = true;
        };
        diff = {
          algorithm = "histogram";
          colorMoved = "default";
          colorMovedWS = "allow-indentation-change";
          renames = true;
        };
        rerere.enabled = true;
        branch.sort = "-committerdate";
        column.ui = "auto";
        fetch = {
          prune = true;
          prunetags = true;
          writeCommitGraph = true;
        };
        push = {
          autoSetupRemote = true;
          followTags = true;
        };
        help.autocorrect = "prompt";
        feature.manyFiles = true;
        pack.threads = 0;
      }
      (lib.mkIf isCerebras {
        push.default = "simple";
        filter.lfs = {
          smudge = "git-lfs smudge -- %f";
          process = "git-lfs filter-process";
          required = true;
          clean = "git-lfs clean -- %f";
        };
        # Credential helpers for github.com and gist.github.com are set
        # automatically by programs.gh.gitCredentialHelper.
      })
    ];

    # On Cerebras, use personal identity for the dotfiles repo itself
    includes = lib.optionals isCerebras [
      {
        condition = "gitdir:${config.home.homeDirectory}/dotfiles-nix/";
        contents.user = {
          name = "jake-edmonstone";
          email = "jbedmonstone@gmail.com";
        };
      }
    ];
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      line-numbers = true;
      navigate = true;
      syntax-theme = "Dracula";
    };
  };

  # gh manages its own ~/.config/gh/config.yml (needs write access for auth).
  # Don't use programs.gh.settings — it makes config.yml read-only and
  # breaks `gh auth login` (cli/cli#4955, home-manager#1654).
  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = true; # wires up git credential helper declaratively
  };

}
