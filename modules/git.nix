{ lib, pkgs, ... }:

{
  programs.git = {
    enable = true;

    # Global gitignore. Content lives in config/git/ignore so non-nix readers
    # can inspect it; the readFile pulls it into the nix-managed list.
    ignores = lib.splitString "\n" (
      lib.strings.removeSuffix "\n" (builtins.readFile ../config/git/ignore)
    );

    settings = {
      # Host modules can override the default personal identity.
      user = {
        name = lib.mkDefault "jake-edmonstone";
        email = lib.mkDefault "jbedmonstone@gmail.com";
      };
      # core.editor is unset: programs.neovim.defaultEditor = true already sets
      # EDITOR=nvim, and git falls back to $EDITOR when core.editor is unset.
      core.fsmonitor = false;
      pull.rebase = true;
      merge.conflictstyle = "zdiff3";
      rebase = {
        autostash = true;
        updateRefs = true;
      };
      diff = {
        algorithm = "histogram";
        colorMoved = "no";
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

  programs.gh.enable = true;
}
