{ lib, ... }:

{
  programs.git = {
    enable = true;

    settings = {
      # Personal identity is the default; Cerebras/work hosts override in their
      # host module (mkDefault so those overrides don't need lib.mkForce).
      user = {
        name = lib.mkDefault "jake-edmonstone";
        email = lib.mkDefault "jbedmonstone@gmail.com";
      };
      core = {
        editor = "nvim";
        fsmonitor = false; # conflicts with gitstatusd (p10k), causes stale prompt
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
        # push.default = "simple" is git's default since 2.0 (2014); no need to set it.
      };
      help.autocorrect = "prompt";
      # feature.manyFiles implies pack.threads=0, index.version=4, core.untrackedCache=true
      # — so we don't set those explicitly. https://git-scm.com/docs/git-config#Documentation/git-config.txt-featuremanyFiles
      feature.manyFiles = true;
      # Modern git (2.40+) also sets index.skipHash=true via feature.manyFiles,
      # which breaks older libgit2 consumers with "invalid data in index —
      # calculated checksum does not match expected". nix-portable bundles
      # nix 2.20.6 (old libgit2), which fails on skipHash'd index files when
      # evaluating flakes. See: https://github.com/libgit2/libgit2/issues/6531
      # Force-disable skipHash so flake evaluation works on nix-portable hosts.
      index.skipHash = false;
    };
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
