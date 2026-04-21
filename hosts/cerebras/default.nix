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
  # Cerebras env. Interactive shells get cbrun via home.sessionPath below —
  # that lands in HM's .zshenv which resolves inside the sandbox.
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

    # cbrun on PATH for interactive shells (via HM's .zshenv inside sandbox).
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
      # Without this, every zsh prompt runs `git rev-parse --show-toplevel`
      # plus a stat on $GITTOP/flow/modulefiles/monolith/default — redundant
      # with p10k's async gitstatusd, which already renders the git segment.
      # Set to 0 (or unset) to re-enable if you rely on flow/devenv.sh
      # auto-loading when cd'ing into a monolith repo.
      ENV_UPDATE_DISABLE = "1";

      ZSH_COMPDUMP = "${config.xdg.cacheHome}/zsh/zcompdump";
    };

    # Cache dir creation is handled downstream: modules/zsh.nix zcompileZshFiles
    # runs `mkdir -p "$zwc_dir"` (same volume) on every activation, zsh creates
    # $ZSH_COMPDUMP's parent on first compinit, and HM's .zshrc creates $HISTFILE's
    # parent. No dedicated mkdir activation needed.

    activation.writeBashExtra = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      cat ${bashrcExtraCerebras} > "$HOME/.bashrc.extra"
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

  # Cache on fast NFS (same volume as ~/.nix). p10k's instant-prompt cache is
  # read on every prompt render, .zcompdump on every shell start — keeping
  # them off the slow home NFS matters. Set via xdg.cacheHome (HM's canonical
  # option) so HM's xdg module writes XDG_CACHE_HOME for us — setting it
  # directly in home.sessionVariables conflicts with HM's own assignment.
  xdg.cacheHome = "/net/jakee-vm/srv/nfs/jakee-data/.cache";

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

  programs.zsh = {
    # EFS fsync on every SHARE_HISTORY append is slow even at 100k; cap at 10k.
    # History file lives on fast NFS (same volume as ~/.nix), not slow EFS home.
    history = {
      size = 10000;
      save = 10000;
      path = "/net/jakee-vm/srv/nfs/jakee-data/.zsh_history";
    };

    shellAliases.fixpath = ''cd ''${PWD/#\/net\/jakee-vm\/srv\/nfs\/jakee-data/~}'';

    initContent = lib.mkMerge [
      # Source the corporate bashrc once per process tree. Tmux splits /
      # subshells inherit the sentinel and PATH, so they skip the 50-500 ms
      # re-source cost. Unset _CB_BASHRC_SOURCED to force re-source.
      # mkOrder 501 sits right after the shared instant-prompt load (mkOrder 500)
      # and before fzf key-bindings (mkOrder 600).
      (lib.mkOrder 501 ''
        if [[ -z "''${_CB_BASHRC_SOURCED:-}" ]]; then
          : "''${PREV_GITTOP:= }"
          global_bashrc="/cb/user_env/bashrc-latest"
          [[ -r "$global_bashrc" ]] && source "$global_bashrc"
          export _CB_BASHRC_SOURCED=1
        fi
      '')

      # Cerebras-specific shell helpers: cbrun wrappers, csapi formatter,
      # bit-pattern inspector. Paths reference `/net/jakee-dev/...` and the
      # corporate `cbrun` command — no meaning off-Cerebras.
      # mkOrder 1001 sits right after the shared user-functions block (1000)
      # and before fast-syntax-highlighting (1400).
      (lib.mkOrder 1001 ''
        csapiformat() {
          local base="/net/jakee-dev/srv/nfs/jakee-data/ws/llvm-project$1/cerebras/csapi"
          "$base/build/run_in_docker.sh" -r "$base" -w "$base" \
            "$base/scripts/format_py.sh" "$base/csapi/"
        }
        show_bits() {
          python3 -c '
        import sys
        h = sys.argv[1].lower().removeprefix("0x")
        v = int(h, 16)
        width = 64 if len(h) > 8 else 32
        bits = f"{v:0{width}b}"
        print(" ".join(f"{i:2d}" for i in range(width-1, -1, -1)))
        print("-" * (3*width))
        print(" ".join(f"{b:>2}" for b in bits))
        ' "$1"
        }
        _cbrun() {
          local cores="$1" target="$2"; shift 2
          MONOLITH_INSTALLROOT="$HOME/ws/monolith-install" \
          INSTALLROOT="$(pwd)/build-install" \
          cbrun -- srun -c"$cores" make "$@" "$target"
        }
        cbformat()   { local j="''${1:-16}"; _cbrun "$j" format }
        cbclean()    { local j="''${1:-16}"; _cbrun "$j" clean }
        cbinstall()  { local j="''${1:-32}"; _cbrun "$j" install }
        cbtest()     { local j="''${1:-32}"; _cbrun "$j" test }
        cbtestci()   { local j="''${1:-32}"; _cbrun "$j" test_ci }
        cbbuild()    { local j="''${1:-32}"; _cbrun "$j" build -j"$j" }
        cbllvmtest() { local j="''${1:-32}"; _cbrun "$j" test_llvm }
        cbcasmtest() { local j="''${1:-32}"; _cbrun "$j" test_casm }
      '')
    ];
  };
}
