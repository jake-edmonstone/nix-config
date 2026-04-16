{ config, pkgs, lib, isCerebras, ... }:

{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    defaultKeymap = "emacs";

    history = {
      size = 100000;
      save = 100000;
      path = "${config.home.homeDirectory}/.zsh_history";
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
      rm = "rm -i";
      cp = "cp -i";
      grep = "grep --ignore-case --color=auto";
      ta = "tmux attach -t";
      tn = "tmux new -s";
      tls = "tmux ls";
      trn = "tmux rename-session";
      lg = "lazygit";
    } // lib.optionalAttrs isCerebras {
      fixpath = ''cd ''${PWD/#\/net\/jakee-vm\/srv\/nfs\/jakee-data/~}'';
    };

    # LOCPATH references HOMEBREW_PREFIX from profileExtra, so must be a
    # zsh-scoped sessionVariable (resolved when zsh profile runs).
    sessionVariables = lib.optionalAttrs isCerebras {
      LOCPATH = "\${HOMEBREW_PREFIX:-}/opt/glibc/lib/locale";
    };

    envExtra = ''
      # Deduplicate PATH, MANPATH, FPATH
      typeset -U path manpath fpath
    '';

    profileExtra = ''
      ${if isCerebras then ''
        # Detect Homebrew prefix
        for _bp in /opt/homebrew /usr/local /home/linuxbrew/.linuxbrew "$HOME/.homebrew"; do
          if [[ -x "$_bp/bin/brew" ]]; then
            eval "$("$_bp/bin/brew" shellenv)"
            break
          fi
        done

        [[ -x "$HOME/.local/bin/curl" ]] && export HOMEBREW_CURL_PATH="$HOME/.local/bin/curl"
        [[ -x "$HOME/.local/bin/git" ]] && export HOMEBREW_GIT_PATH="$HOME/.local/bin/git"
      '' else ''
        # Homebrew (macOS)
        export HOMEBREW_PREFIX="/opt/homebrew"
        export HOMEBREW_CELLAR="/opt/homebrew/Cellar"
        export HOMEBREW_REPOSITORY="/opt/homebrew"
        fpath[1,0]="/opt/homebrew/share/zsh/site-functions"
        export FPATH
        export PATH="/opt/homebrew/bin:/opt/homebrew/sbin''${PATH+:$PATH}"
        [[ -z "''${MANPATH-}" ]] || export MANPATH=":''${MANPATH#:}"
        export INFOPATH="/opt/homebrew/share/info:''${INFOPATH:-}"
      ''}
      path=(
        $HOME/.local/share/nvim/mason/bin
        $HOME/.local/bin
        $path
      )
    '';

    initContent = lib.mkMerge [
      # ── Instant prompt (must be very first) ──────────────────────────────
      (lib.mkOrder 500 ''
        if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
          source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
        fi
        ${lib.optionalString isCerebras ''
          : "''${PREV_GITTOP:= }"
          global_bashrc="/cb/user_env/bashrc-latest"
          [[ -r "$global_bashrc" ]] && source "$global_bashrc"
        ''}
      '')

      # ── fzf-tab (after compinit, before autosuggestions) ─────────────────
      (lib.mkOrder 600 ''
        source ${pkgs.zsh-fzf-tab}/share/fzf-tab/fzf-tab.plugin.zsh
        zstyle ':fzf-tab:*' use-fzf-default-opts yes
        zstyle ':fzf-tab:*' prefix ""
        zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
      '')

      # ── General config ───────────────────────────────────────────────────
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
        trash() { mv "$@" ~/.Trash }

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
          cbformat() { MONOLITH_INSTALLROOT="$HOME/ws/monolith-install" INSTALLROOT="$(pwd)/build-install" cbrun -- srun -c16 make format }
          cbclean() { MONOLITH_INSTALLROOT="$HOME/ws/monolith-install" INSTALLROOT="$(pwd)/build-install" cbrun -- srun -c16 make clean }
          cbbuild() {
            local jobs="''${1:-32}"
            MONOLITH_INSTALLROOT="$HOME/ws/monolith-install" \
            INSTALLROOT="$(pwd)/build-install" \
            cbrun -- srun -c"$jobs" make -j"$jobs" build
          }
          cbinstall() { MONOLITH_INSTALLROOT="$HOME/ws/monolith-install" INSTALLROOT="$(pwd)/build-install" cbrun -- srun -c32 make install }
          cbtest() { MONOLITH_INSTALLROOT="$HOME/ws/monolith-install" INSTALLROOT="$(pwd)/build-install" cbrun -- srun -c32 make test }
          cbtestci() { MONOLITH_INSTALLROOT="$HOME/ws/monolith-install" INSTALLROOT="$(pwd)/build-install" cbrun -- srun -c32 make test_ci }
          cbllvmtest() {
            local jobs="''${1:-32}"
            MONOLITH_INSTALLROOT="$HOME/ws/monolith-install" INSTALLROOT="$(pwd)/build-install" cbrun -- srun -c"$jobs" make test_llvm
          }
          cbcasmtest() {
            local jobs="''${1:-32}"
            MONOLITH_INSTALLROOT="$HOME/ws/monolith-install" INSTALLROOT="$(pwd)/build-install" cbrun -- srun -c"$jobs" make test_casm
          }
        ''}
      '')

      # ── Powerlevel10k (after everything else) ────────────────────────────
      (lib.mkOrder 1500 ''
        source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme
        [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
      '')
    ];
  };
}
