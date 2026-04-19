{ lib, pkgs, ... }:

let
  # ~/.bashrc is managed by install.sh as a REAL file (not via programs.bash).
  # Reason: home-manager would write it as a symlink into /nix/store, which on
  # rootless Nix isn't accessible at SSH login — the symlink would dangle and
  # bash couldn't read it, so the exec-into-chroot bootstrap would never fire.
  # install.sh's bootstrap ~/.bashrc sources ~/.bashrc.extra if present — we
  # materialize it here with Cerebras-specific env so it's a real file too,
  # readable before entering the chroot.
  bashrcExtraCerebras = pkgs.writeText "bashrc-extra-cerebras" ''
    # Managed by home-manager (hosts/cerebras/default.nix). Cerebras-specific env.
    if [[ $- == *i* ]]; then
      # Interactive: put Cerebras's cbrun on PATH.
      export PATH="/cb/tools/cerebras/cbrun/v0.3.3:$PATH"
    elif [[ -z "''${MAKELEVEL:-}" \
         && -z "''${NIX_BUILD_TOP:-}" \
         && -z "''${IN_NIX_SHELL:-}" ]]; then
      # Non-interactive top-level shell (ssh host cmd, cron): source the full
      # Cerebras env. Skip for Make/Nix subshells — they inherit env from the
      # user's interactive shell already, and `module load` inside a nix build
      # would also break sandbox hermeticity.
      global_bashrc="/cb/user_env/bashrc-latest"
      [ -r "$global_bashrc" ] && . "$global_bashrc"
    fi
  '';
in

{
  home.username = "jakee";
  home.homeDirectory = "/cb/home/jakee";

  home.sessionVariables = {
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

    # Cache + compdump on the fast NFS mount (same volume as ~/.nix, which is
    # symlinked to /net/jakee-vm/srv/nfs/jakee-data/.nix). p10k's instant-prompt
    # cache is read on every prompt render, and .zcompdump is stat+read'd on
    # every shell start — keeping them off the slow home NFS matters.
    XDG_CACHE_HOME = "/net/jakee-vm/srv/nfs/jakee-data/.cache";
    ZSH_COMPDUMP = "/net/jakee-vm/srv/nfs/jakee-data/.cache/zsh/zcompdump";
  };

  # Cache dir creation is handled downstream: modules/zsh.nix zcompileZshFiles
  # runs `mkdir -p "$zwc_dir"` (same volume) on every activation, zsh creates
  # $ZSH_COMPDUMP's parent on first compinit, and HM's .zshrc creates $HISTFILE's
  # parent. No dedicated mkdir activation needed.

  home.activation.writeBashExtra = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    cat ${bashrcExtraCerebras} > "$HOME/.bashrc.extra"
  '';
}
