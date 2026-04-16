{ config, lib, pkgs, isCerebras, ... }:

{
  programs.git = {
    enable = true;

    settings = {
      user = {
        name = if isCerebras then "Jake Edmonstone" else "jake-edmonstone";
        email = if isCerebras then "jake.edmonstone@cerebras.net" else "jbedmonstone@gmail.com";
      };
      core = {
        editor = "nvim";
        fsmonitor = true;
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
      } // lib.optionalAttrs isCerebras {
        default = "simple";
      };
      help.autocorrect = "prompt";
      feature.manyFiles = true;
      pack.threads = 0;
    } // lib.optionalAttrs isCerebras {
      filter.lfs = {
        smudge = "git-lfs smudge -- %f";
        process = "git-lfs filter-process";
        required = true;
        clean = "git-lfs clean -- %f";
      };
      "credential \"https://github.com\"" = {
        helper = [
          ""
          "!${config.home.homeDirectory}/.homebrew/bin/gh auth git-credential"
        ];
      };
      "credential \"https://gist.github.com\"" = {
        helper = [
          ""
          "!${config.home.homeDirectory}/.homebrew/bin/gh auth git-credential"
        ];
      };
    };

    includes = lib.optionals isCerebras [
      {
        condition = "gitdir:${config.home.homeDirectory}/dotfiles-nix/";
        path = "${config.home.homeDirectory}/.gitconfig-personal";
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

  home.file.".gitconfig-personal".text = ''
    [user]
    	name = jake-edmonstone
    	email = jbedmonstone@gmail.com
  '';
}
