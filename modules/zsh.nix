{ config, pkgs, lib, isCerebras, ... }:

{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    # Rebuild the compdump once per 24h; fast-path (-C) otherwise. -C skips the
    # insecure-dir security check AND the dump-rebuild, which is the expensive
    # part. Respects $ZSH_COMPDUMP so Cerebras can point it at local scratch.
    # Background-compile the dump to .zwc so the next shell loads bytecode.
    completionInit = ''
      autoload -Uz compinit
      _zcd=''${ZSH_COMPDUMP:-''${ZDOTDIR:-$HOME}/.zcompdump}
      _stale=( $_zcd(Nmh+24) )
      if [[ -s $_zcd ]] && (( ! ''${#_stale} )); then
        compinit -C -d $_zcd
      else
        compinit -d $_zcd
      fi
      { [[ -s $_zcd && ( ! -s $_zcd.zwc || $_zcd -nt $_zcd.zwc ) ]] && zcompile $_zcd } &!
      unset _zcd _stale
    '';
    autosuggestion.enable = true;
    # Use fast-syntax-highlighting (sourced in initContent below) instead of
    # zsh-syntax-highlighting: drop-in replacement with materially less
    # per-keystroke work — ~25% of interactive shell startup on cold caches.
    syntaxHighlighting.enable = false;
    defaultKeymap = "emacs";

    history = {
      # Smaller on Cerebras: SHARE_HISTORY appends+fsyncs the history file each
      # prompt; on EFS (home dir) that's materially slow even at 100k capped.
      size = if isCerebras then 10000 else 100000;
      save = if isCerebras then 10000 else 100000;
      # On Cerebras, move history off slow EFS onto the fast NFS volume where
      # ~/.nix already lives. Mac keeps it in $HOME (fast local APFS).
      path =
        if isCerebras
        then "/net/jakee-vm/srv/nfs/jakee-data/.zsh_history"
        else "${config.home.homeDirectory}/.zsh_history";
      ignoreDups = true;
      ignoreSpace = true;
      findNoDups = true;
      extended = true;
      share = true;
    };

    historySubstringSearch.enable = false;

    setOptions = [
      "HIST_REDUCE_BLANKS"
      # INC_APPEND_HISTORY dropped — mutually exclusive with SHARE_HISTORY (history.share = true)
    ];

    shellAliases = {
      grep = "grep --ignore-case --color=auto";
      ta = "tmux attach -t";
      tn = "tmux new -s";
      tls = "tmux ls";
      trn = "tmux rename-session";
      lg = "lazygit";
    } // lib.optionalAttrs isCerebras {
      fixpath = ''cd ''${PWD/#\/net\/jakee-vm\/srv\/nfs\/jakee-data/~}'';
    };

    envExtra = ''
      # Deduplicate PATH, MANPATH, FPATH (zsh-specific; no HM equivalent)
      typeset -U path manpath fpath
      # NOTE on $USERNAME: on SSS/LDAP hosts where the user isn't in
      # /etc/passwd directly, nix's glibc can't resolve via nss_sss, so zsh's
      # getpwuid-backed $USERNAME getter returns "". No assignment in zshenv
      # can stick because zsh re-reads the getter on every access. The fix
      # lives in ~/.p10k.zsh, which uses $USER (set by PAM) instead of %n.
    '';

    initContent = lib.mkMerge [
      # Rootless Nix: re-exec into user-namespace chroot if nix-user-chroot is
      # installed and we're not already inside. No-op on macOS / daemon setups.
      (lib.mkOrder 100 (lib.optionalString pkgs.stdenv.isLinux ''
        # Sweep stale /tmp/nix-chroot.* dirs from sessions killed by SIGKILL/OOM/
        # abrupt SSH drop (nix-user-chroot's cleanup only runs on clean exit).
        # Same logic lives in install.sh's generated ~/.bashrc — this branch
        # covers zsh-as-login-shell hosts where bash never runs. Single grep
        # over all /proc/*/mountinfo: ~10x faster than a per-file awk loop.
        if [[ -z "''${NIX_USER_CHROOT:-}" ]]; then
          local _live_roots _dir _now _mt
          _live_roots=$(grep -ohE '/tmp/nix-chroot\.[A-Za-z0-9]+' /proc/[0-9]*/mountinfo 2>/dev/null | sort -u)
          _now=$(date +%s 2>/dev/null)
          for _dir in /tmp/nix-chroot.*(N); do
            [[ -d "$_dir" && -O "$_dir" ]] || continue
            _mt=$(stat -c %Y "$_dir" 2>/dev/null) || continue
            (( _now - _mt < 5 )) && continue
            print -r -- "$_live_roots" | grep -qxF "$_dir" && continue
            rm -rf -- "$_dir" 2>/dev/null || true
          done
        fi

        if [[ -x "$HOME/.local/bin/nix-user-chroot" \
           && -d "$HOME/.nix" \
           && -z "''${NIX_USER_CHROOT:-}" ]]; then
          export NIX_USER_CHROOT=1
          exec "$HOME/.local/bin/nix-user-chroot" "$HOME/.nix" /usr/bin/env zsh -l "$@"
        fi
      ''))

      # Instant prompt — must be very first
      (lib.mkOrder 500 ''
        if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
          source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
        fi
        ${lib.optionalString isCerebras ''
          # Source the corporate bashrc once per process tree. Tmux splits /
          # subshells inherit the sentinel and PATH, so they skip the 50-500 ms
          # re-source cost. Unset _CB_BASHRC_SOURCED to force re-source.
          if [[ -z "''${_CB_BASHRC_SOURCED:-}" ]]; then
            : "''${PREV_GITTOP:= }"
            global_bashrc="/cb/user_env/bashrc-latest"
            [[ -r "$global_bashrc" ]] && source "$global_bashrc"
            export _CB_BASHRC_SOURCED=1
          fi
        ''}
      '')

      # fzf-tab — after compinit, before autosuggestions
      (lib.mkOrder 600 ''
        source ${pkgs.zsh-fzf-tab}/share/fzf-tab/fzf-tab.plugin.zsh
        zstyle ':fzf-tab:*' use-fzf-default-opts yes
        zstyle ':fzf-tab:*' prefix ""
        zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
      '')

      # fzf key bindings + completion — sourced from the nix store directly
      # instead of `source <(fzf --zsh)` (the programs.fzf.enableZshIntegration
      # default), which forks fzf once per shell startup. On macOS with EDR in
      # the mix that's ~6 ms of pure overhead per spawn.
      (lib.mkOrder 650 ''
        source ${pkgs.fzf}/share/fzf/key-bindings.zsh
        source ${pkgs.fzf}/share/fzf/completion.zsh
      '')

      # zsh-autosuggestions perf knobs — sourced after the plugin is enabled by
      # home-manager (programs.zsh.autosuggestion.enable).
      # MANUAL_REBIND avoids the well-known 200 ms precmd rebind (upstream #544).
      # BUFFER_MAX_SIZE skips suggestions on huge pastes.
      (lib.mkOrder 700 ''
        ZSH_AUTOSUGGEST_MANUAL_REBIND=1
        ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
        ZSH_AUTOSUGGEST_STRATEGY=(history)
      '')

      (lib.mkOrder 1000 ''
        _fzf_compgen_path() { fd --hidden . "$1" }
        _fzf_compgen_dir()  { fd --type=d --hidden . "$1" }

        _fzf_comprun() {
          local cmd=$1; shift
          case "$cmd" in
            cd)           fzf --preview 'eza --tree --color=always {} | head -200' "$@" ;;
            export|unset) fzf --preview 'eval echo \''${}' "$@" ;;
            ssh)          fzf --preview 'dig {}'                   "$@" ;;
            *)            fzf --preview "bat -n --color=always --line-range :500 {}" "$@" ;;
          esac
        }

        # Ctrl-X Ctrl-E opens command line in $EDITOR
        autoload -Uz edit-command-line
        zle -N edit-command-line
        bindkey '^x^e' edit-command-line

        # Blinking block cursor
        printf '\e[1 q'

        # Functions
        mkcd() { mkdir -p "$1" && cd "$1" }
        rebuild() {
          case "$(uname -s)" in
            Darwin) sudo -H "$(command -v darwin-rebuild)" switch "$@" ;;
            Linux)  home-manager switch --flake "$DOTFILES" "$@" ;;
            *)      echo "rebuild: unsupported OS: $(uname -s)" >&2; return 1 ;;
          esac
        }

        ${lib.optionalString isCerebras ''
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
        ''}
      '')

      # fast-syntax-highlighting — must come after any plugin that adds
      # aliases/functions (fzf-tab, edit-command-line, etc.), before p10k.
      (lib.mkOrder 1400 ''
        source ${pkgs.zsh-fast-syntax-highlighting}/share/zsh/plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh
      '')

      # Powerlevel10k — after everything else
      (lib.mkOrder 1500 ''
        source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme
        [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
      '')
    ];
  };

  # Compile the big zsh source files to .zwc bytecode on every activation so
  # zsh loads them via mmap instead of re-parsing. ~10-25 ms cold-start saving.
  # ~/.zshrc and ~/.zshenv are symlinks into the nix store; zcompile reads the
  # target but writes .zwc next to the symlink. We rebuild unconditionally
  # because nix-store mtimes are frozen to epoch so a -nt check would never
  # trigger; activations are rare (only on HM switch).
  #
  # On Cerebras, $HOME is slow EFS — writing .zwc there would negate the win,
  # since reading the .zwc over EFS can cost as much as parsing the source that
  # lives on fast NFS via the ~/.nix bind mount. So we compile to fast NFS and
  # symlink $HOME/.FILE.zwc → that location.
  home.activation.zcompileZshFiles = lib.hm.dag.entryAfter [ "writeBoundary" ] (
    if isCerebras then ''
      zwc_dir="/net/jakee-vm/srv/nfs/jakee-data/.cache/zsh/zwc"
      mkdir -p "$zwc_dir"
      for name in zshrc zshenv p10k.zsh; do
        src="$HOME/.$name"
        out="$zwc_dir/$name.zwc"
        if [[ -f "$src" ]]; then
          ${pkgs.zsh}/bin/zsh -c "zcompile -R '$out' '$src'" 2>/dev/null \
            && ln -sfn "$out" "$src.zwc"
        fi
      done
    '' else ''
      for f in "$HOME/.zshrc" "$HOME/.zshenv" "$HOME/.p10k.zsh"; do
        if [[ -f "$f" ]]; then
          ${pkgs.zsh}/bin/zsh -c "zcompile -R '$f'" 2>/dev/null || true
        fi
      done
    ''
  );
}
