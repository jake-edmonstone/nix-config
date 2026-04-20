{ config, lib, ... }:

{
  imports = [
    ./common.nix
    ../hosts/cerebras
  ];

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

  # Claude Code overrides for Cerebras:
  # 1. Append Cerebras-specific C++ style rules to CLAUDE.md.
  # 2. Add claudeMdExcludes so Claude skips the huge /net/* NFS tree when
  #    auto-discovering CLAUDE.md in parent directories.
  home.file.".claude/CLAUDE.md".text = lib.mkForce (
    builtins.readFile ../config/claude/CLAUDE.md
    + builtins.readFile ../config/claude/CLAUDE.cerebras.md
  );

  home.file.".claude/settings.json".text = lib.mkForce (builtins.toJSON (
    (import ../config/claude/settings.nix { inherit config; }) // {
      claudeMdExcludes = [
        "/net/*"
        "/net/*/*/"
      ];
    }
  ));
}
