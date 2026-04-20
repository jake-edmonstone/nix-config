{ config, pkgs, lib, isRootlessLinux, isCerebras, ... }:

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
      size = 100000;
      save = 100000;
      ignoreDups = true;
      ignoreSpace = true;
      findNoDups = true;
      extended = true;
      share = true;
    };

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
      # NB: no `lg` alias — programs.lazygit already injects an `lg()` zsh
      # function that cd's back if lazygit wrote a newdir sentinel. A plain
      # alias would be shadowed anyway (functions beat aliases in zsh resolution).
    };

    envExtra = ''
      # Deduplicate PATH, MANPATH, FPATH (zsh-specific; no HM equivalent)
      typeset -U path manpath fpath
      # NOTE on $USERNAME: on SSS/LDAP hosts where the user isn't in
      # /etc/passwd directly, nix's glibc can't resolve via nss_sss, so zsh's
      # getpwuid-backed $USERNAME getter returns "". No assignment in zshenv
      # can stick because zsh re-reads the getter on every access. The fix
      # lives in ~/.p10k.zsh, which uses $USER (set by PAM) instead of %n.

      # Pre-seed P9K_SSH so p10k skips its internal _p9k_init_ssh probe
      # (measured ~11 ms, 26% of zsh cold startup). The probe gathers info we
      # already have via standard SSH env vars.
      if [[ -n "''${SSH_CONNECTION:-}" || -n "''${SSH_CLIENT:-}" || -n "''${SSH_TTY:-}" ]]; then
        typeset -g P9K_SSH=1
      else
        typeset -g P9K_SSH=0
      fi

    '' + lib.optionalString isRootlessLinux ''
      # On nix-portable hosts, the sandbox is entered via
      # `nix-portable nix run nixpkgs#zsh -- -l` which sets PATH to zsh's
      # runtime deps only — nix itself isn't propagated. Home-manager's
      # doBuildFlake function runs `nix` internally and fails with
      # "nix: command not found" when the bundled nix isn't on PATH.
      # Bake a specific ${pkgs.nix}/bin (from nixpkgs) into PATH at Nix eval
      # time; NP_ENTERED gates runtime (only nix-portable hosts ever set it;
      # nix-user-chroot hosts — Cerebras — get nix on PATH another way via
      # the chroot re-exec's PATH setup). This whole lib.optionalString is
      # emitted only on isRootlessLinux hosts, so Mac's .zshenv doesn't
      # reference pkgs.nix at all.
      if [[ -n "''${NP_ENTERED:-}" ]] && ! (( $+commands[nix] )); then
        export PATH="${pkgs.nix}/bin:$PATH"
      fi
    '';

    initContent = lib.mkMerge [
      # Instant prompt — must be very first. Sandbox entry is handled by the
      # install.sh-written ~/.bash_profile → ~/.bashrc → ~/.nix-bootstrap.sh
      # chain, which execs zsh -l inside the sandbox, so by the time this
      # HM-managed .zshrc is read we're already inside.
      (lib.mkOrder 500 ''
        if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
          source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
        fi
      '')

      # fzf key bindings + completion — sourced from the nix store directly
      # instead of `source <(fzf --zsh)` (the programs.fzf.enableZshIntegration
      # default), which forks fzf once per shell startup. On macOS with EDR in
      # the mix that's ~6 ms of pure overhead per spawn.
      # MUST come BEFORE fzf-tab: fzf-tab's README requires it to be the last
      # plugin to bind ^I, and fzf's completion.zsh also binds ^I.
      (lib.mkOrder 600 ''
        source ${pkgs.fzf}/share/fzf/key-bindings.zsh
        source ${pkgs.fzf}/share/fzf/completion.zsh
      '')

      # fzf-tab — after compinit and after fzf's own bindings
      (lib.mkOrder 650 ''
        source ${pkgs.zsh-fzf-tab}/share/fzf-tab/fzf-tab.plugin.zsh
        zstyle ':fzf-tab:*' use-fzf-default-opts yes
        zstyle ':fzf-tab:*' prefix ""
        zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
      '')

      # zsh-autosuggestions perf knobs — emitted before HM's plugin-source line
      # so they take effect on first precmd.
      # MANUAL_REBIND avoids the well-known 200 ms precmd rebind (upstream #544).
      # BUFFER_MAX_SIZE skips suggestions on huge pastes.
      # (STRATEGY=(history) is already HM's default via programs.zsh.autosuggestion.strategy.)
      (lib.mkOrder 700 ''
        ZSH_AUTOSUGGEST_MANUAL_REBIND=1
        ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
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

        # Re-assert blinking block cursor on every prompt. A one-shot printf at
        # shell start gets clobbered when TUI apps (nvim, yazi, lazygit, etc.)
        # change the cursor shape on entry and fail to fully restore it on exit
        # — a known Ghostty quirk (ghostty-org/ghostty#9209). Ghostty's
        # `cursor-style-blink = true` only sets the DEFAULT; DECSCUSR state
        # from the last child TUI wins until something overrides it.
        _cursor_blinking_block() { printf '\e[1 q' }
        precmd_functions+=(_cursor_blinking_block)

        # Functions
        mkcd() { mkdir -p "$1" && cd "$1" }
        # On hosts where $USER@$(hostname) matches the flake attr, leave
        # REBUILD_FLAKE_ATTR unset and home-manager's auto-resolve picks it up.
        # On hosts where hostname churns (UWaterloo student CS: interchangeable
        # ubuntu2404-NNN boxes), the host sets REBUILD_FLAKE_ATTR in
        # home.sessionVariables so this function targets the right config.
        rebuild() {
          case "$(uname -s)" in
            Darwin) sudo -H "$(command -v darwin-rebuild)" switch "$@" ;;
            Linux)  home-manager switch --flake "$DOTFILES''${REBUILD_FLAKE_ATTR:+#$REBUILD_FLAKE_ATTR}" "$@" ;;
            *)      echo "rebuild: unsupported OS: $(uname -s)" >&2; return 1 ;;
          esac
        }
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
  # With xdg.enable = true, HM places .zshrc and the "real" .zshenv under
  # $HOME/${programs.zsh.dotDir} (defaults to ".config/zsh" on Mac here), with
  # a small stub .zshenv at $HOME that sources the real one. We compile all
  # three plus ~/.p10k.zsh. zcompile reads the symlink target but writes .zwc
  # next to the symlink (in $HOME/$dotDir, writable). We rebuild unconditionally
  # because nix-store mtimes are frozen so a -nt check would never trigger;
  # activations are rare.
  #
  # On Cerebras, $HOME is slow EFS. Writing .zwc there would negate the win.
  # So we compile to fast NFS and symlink the target location → fast NFS path.
  home.activation.zcompileZshFiles = let
    # In current home-manager, programs.zsh.dotDir is an absolute path (e.g.
    # /Users/jbedm/.config/zsh) — not relative to $HOME. Do NOT prepend home.
    zshDir = config.programs.zsh.dotDir;
    files = [
      "${zshDir}/.zshrc"
      "${zshDir}/.zshenv"
      "${config.home.homeDirectory}/.zshenv"
      "${config.home.homeDirectory}/.p10k.zsh"
    ];
  in lib.hm.dag.entryAfter [ "writeBoundary" ] (
    if isCerebras then ''
      zwc_dir="/net/jakee-vm/srv/nfs/jakee-data/.cache/zsh/zwc"
      mkdir -p "$zwc_dir"
      _idx=0
      for src in ${lib.concatMapStringsSep " " (f: "\"${f}\"") files}; do
        _idx=$((_idx+1))
        out="$zwc_dir/zsh-$_idx.zwc"
        if [[ -f "$src" ]]; then
          ${pkgs.zsh}/bin/zsh -c "zcompile -R '$out' '$src'" 2>/dev/null \
            && ln -sfn "$out" "$src.zwc"
        fi
      done
      unset _idx
    '' else ''
      for f in ${lib.concatMapStringsSep " " (f: "\"${f}\"") files}; do
        if [[ -f "$f" ]]; then
          ${pkgs.zsh}/bin/zsh -c "zcompile -R '$f'" 2>/dev/null || true
        fi
      done
    ''
  );
}
