{ config, pkgs, lib, isCerebras, ... }:

{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    # -C skips the slow insecure-directory check. Safe in single-user setups.
    completionInit = "autoload -U compinit && compinit -C";
    autosuggestion.enable = true;
    # Use fast-syntax-highlighting (sourced in initContent below) instead of
    # zsh-syntax-highlighting: drop-in replacement with materially less
    # per-keystroke work — ~25% of interactive shell startup on cold caches.
    syntaxHighlighting.enable = false;
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
          : "''${PREV_GITTOP:= }"
          global_bashrc="/cb/user_env/bashrc-latest"
          [[ -r "$global_bashrc" ]] && source "$global_bashrc"
        ''}
      '')

      # fzf-tab — after compinit, before autosuggestions
      (lib.mkOrder 600 ''
        source ${pkgs.zsh-fzf-tab}/share/fzf-tab/fzf-tab.plugin.zsh
        zstyle ':fzf-tab:*' use-fzf-default-opts yes
        zstyle ':fzf-tab:*' prefix ""
        zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
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
}
