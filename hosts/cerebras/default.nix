{
  config,
  lib,
  pkgs,
  ...
}:

let
  # ~/.bashrc is managed by install.sh as a REAL file (not via programs.bash).
  # Reason: home-manager would write it as a symlink into /nix/store, which on
  # rootless Nix isn't accessible at SSH login — the symlink would dangle and
  # bash couldn't read it, so the exec-into-chroot bootstrap would never fire.
  # install.sh's bootstrap ~/.bashrc sources ~/.bashrc.extra if present — we
  # materialize it here with Cerebras-specific env so it's a real file too,
  # readable before entering the chroot.
  # Non-interactive top-level shells (ssh host cmd, cron) need the full
  # Cerebras env. Interactive shells get cbrun via home.sessionPath below.
  # Skip for Make/Nix subshells: they inherit env from the interactive shell
  # already, and `module load` inside a nix build breaks sandbox hermeticity.
  bashrcExtraCerebras = pkgs.writeText "bashrc-extra-cerebras" ''
    # Managed by home-manager (hosts/cerebras/default.nix). Cerebras-specific env.
    case $- in *i*) ;; *)
      if [ -z "''${MAKELEVEL:-}" ] && [ -z "''${NIX_BUILD_TOP:-}" ] && [ -z "''${IN_NIX_SHELL:-}" ]; then
        [ -r /cb/user_env/bashrc-latest ] && . /cb/user_env/bashrc-latest
      fi
    ;; esac
  '';
in

{
  imports = [ ../../home/common.nix ];

  home = {
    username = "jakee";
    homeDirectory = "/cb/home/jakee";

    # cbrun on PATH for interactive shells inside the sandbox.
    # Non-interactive shells that need corp tools go through bashrcExtraCerebras
    # which sources the full /cb/user_env/bashrc-latest.
    sessionPath = [ "/cb/tools/cerebras/cbrun/v0.3.3" ];

    sessionVariables = {
      # Match the host glibc's locale dir name (RHEL/Rocky uses lowercase
      # en_US.utf8, not en_US.UTF-8). With the default uppercase LANG, glibc
      # probes the nonexistent capitalized dir for every LC_* category on
      # every process start — ~240 wasted syscalls per shell.
      LANG = "en_US.utf8";

      # Short-circuit /cb/user_env/bashrc-latest's env_update precmd hook.
      # Without this, the corporate prompt hook runs `git rev-parse
      # --show-toplevel` plus a stat on $GITTOP/flow/modulefiles/monolith/default
      # on every prompt. Fish/Tide renders its own git segment, so keep the
      # corporate hook disabled.
      # Set to 0 (or unset) to re-enable if you rely on flow/devenv.sh
      # auto-loading when cd'ing into a monolith repo.
      ENV_UPDATE_DISABLE = "1";
    };

    activation.writeBashExtra = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      cat ${bashrcExtraCerebras} > "$HOME/.bashrc.extra"
      mkdir -p "${config.xdg.dataHome}/fish"
    '';

    # Claude Code overrides for Cerebras:
    # 1. Append Cerebras-specific C++ style rules to CLAUDE.md.
    # 2. Add claudeMdExcludes so Claude skips the huge /net/* NFS tree when
    #    auto-discovering CLAUDE.md in parent directories.
    # No lib.mkForce needed — modules/claude.nix uses lib.mkDefault on the
    # base values, so an unqualified assignment here wins.
    file.".claude/CLAUDE.md".text =
      builtins.readFile ../../config/claude/CLAUDE.md
      + builtins.readFile ../../config/claude/CLAUDE.cerebras.md;

    file.".claude/settings.json".text = builtins.toJSON (
      (import ../../config/claude/settings.nix { inherit config; })
      // {
        claudeMdExcludes = [
          "/net/*"
          "/net/*/*/"
        ];
      }
    );
  };

  # Cache/data on fast NFS (same volume as ~/.nix). Fish history lives under
  # XDG_DATA_HOME and Tide/fish caches live under XDG_CACHE_HOME, so keep both
  # off the slow EFS home. Set via HM's canonical xdg options so it writes the
  # environment consistently.
  xdg.cacheHome = "/net/jakee-vm/srv/nfs/jakee-data/.cache";
  xdg.dataHome = "/net/jakee-vm/srv/nfs/jakee-data/.local/share";

  # Cerebras identity. Personal identity lives in modules/git.nix as the
  # default; the nix-config repo still commits under personal email via the
  # includeIf below.
  programs.git = {
    settings.user = {
      name = "Jake Edmonstone";
      email = "jake.edmonstone@cerebras.net";
    };
    includes = [
      {
        condition = "gitdir:${config.home.homeDirectory}/nix-config/";
        contents.user = {
          name = "jake-edmonstone";
          email = "jbedmonstone@gmail.com";
        };
      }
    ];
    lfs.enable = true;
  };

  programs.fish = {
    plugins = [
      {
        name = "bass";
        src = pkgs.fishPlugins.bass.src;
      }
    ];

    shellAliases.fixpath = "fixpath";

    functions = {
      fixpath = ''
        cd (string replace -r '^/net/jakee-vm/srv/nfs/jakee-data' '~' -- "$PWD")
      '';

      csapiformat = ''
        set -l base "/net/jakee-dev/srv/nfs/jakee-data/ws/llvm-project$argv[1]/cerebras/csapi"
        "$base/build/run_in_docker.sh" -r "$base" -w "$base" "$base/scripts/format_py.sh" "$base/csapi/"
      '';

      show_bits = ''
        python3 -c '
        import sys
        h = sys.argv[1].lower().removeprefix("0x")
        v = int(h, 16)
        width = 64 if len(h) > 8 else 32
        bits = f"{v:0{width}b}"
        print(" ".join(f"{i:2d}" for i in range(width-1, -1, -1)))
        print("-" * (3*width))
        print(" ".join(f"{b:>2}" for b in bits))
        ' $argv[1]
      '';

      _cbrun = ''
        set -l cores $argv[1]
        set -l target $argv[2]
        set -l rest $argv[3..-1]
        env MONOLITH_INSTALLROOT="$HOME/ws/monolith-install" INSTALLROOT="$(pwd)/build-install" \
          cbrun -- srun -c"$cores" make $rest "$target"
      '';

      cbformat = ''set -l j 16; test (count $argv) -gt 0; and set j "$argv[1]"; _cbrun "$j" format'';
      cbclean = ''set -l j 16; test (count $argv) -gt 0; and set j "$argv[1]"; _cbrun "$j" clean'';
      cbinstall = ''set -l j 32; test (count $argv) -gt 0; and set j "$argv[1]"; _cbrun "$j" install'';
      cbtest = ''set -l j 32; test (count $argv) -gt 0; and set j "$argv[1]"; _cbrun "$j" test'';
      cbtestci = ''set -l j 32; test (count $argv) -gt 0; and set j "$argv[1]"; _cbrun "$j" test_ci'';
      cbbuild = ''set -l j 32; test (count $argv) -gt 0; and set j "$argv[1]"; _cbrun "$j" build -j"$j"'';
      cbllvmtest = ''set -l j 32; test (count $argv) -gt 0; and set j "$argv[1]"; _cbrun "$j" test_llvm'';
      cbcasmtest = ''set -l j 32; test (count $argv) -gt 0; and set j "$argv[1]"; _cbrun "$j" test_casm'';
    };

    interactiveShellInit = lib.mkMerge [
      # Source the corporate bashrc once per process tree. Tmux splits /
      # subshells inherit the sentinel and PATH, so they skip the 50-500 ms
      # re-source cost. Unset _CB_BASHRC_SOURCED to force re-source.
      (lib.mkOrder 501 ''
        if not set -q _CB_BASHRC_SOURCED
          set -q PREV_GITTOP; or set -gx PREV_GITTOP " "
          set -l global_bashrc /cb/user_env/bashrc-latest
          test -r "$global_bashrc"; and bass source "$global_bashrc"
          set -gx _CB_BASHRC_SOURCED 1
        end
      '')
    ];
  };
}
