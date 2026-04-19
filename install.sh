#!/usr/bin/env bash
set -euo pipefail

msg()  { printf "\033[1;32m==>\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33mWARNING:\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31mERROR:\033[0m %s\n" "$*" >&2; }

DOTFILES="$(cd "$(dirname "$0")" && pwd)"

# nix-user-chroot pin (bump when a new release is tagged)
NIX_USER_CHROOT_VERSION="2.1.1"
NIX_USER_CHROOT="$HOME/.local/bin/nix-user-chroot"
NIX_ROOT="$HOME/.nix"

# nix-portable pin (fallback when AppArmor blocks user namespaces — Ubuntu 23.10+)
NIX_PORTABLE_VERSION="v012"
NIX_PORTABLE="$HOME/.local/bin/nix-portable"

is_darwin() { [[ "$(uname -s)" == "Darwin" ]]; }
# Can we become root without an interactive prompt?
can_sudo() { [[ "$EUID" -eq 0 ]] || sudo -n true 2>/dev/null; }

# Install-state predicates. Rootless uses a sentinel file so a half-downloaded
# or interrupted install doesn't claim completion because a stray binary exists.
has_nix_on_path()  { command -v nix >/dev/null 2>&1; }
has_nix_daemon()   { [[ -x /nix/var/nix/profiles/default/bin/nix ]]; }
has_nix_rootless() { [[ -f "$NIX_ROOT/.install-complete" ]]; }
has_nix_portable() { [[ -x "$NIX_PORTABLE" ]]; }

# ──────────────────────────────────────────────────────────────────────────────
# macOS prerequisites
# ──────────────────────────────────────────────────────────────────────────────
if is_darwin; then
  if ! xcode-select -p >/dev/null 2>&1; then
    msg "Installing Xcode Command Line Tools"
    xcode-select --install
    echo "Finish the CLT install in the popup, then re-run this script."
    exit 0
  fi

  if [[ "$(uname -m)" == "arm64" ]] && ! /usr/bin/pgrep oahd >/dev/null 2>&1; then
    msg "Installing Rosetta 2"
    softwareupdate --install-rosetta --agree-to-license
  fi
fi

# ──────────────────────────────────────────────────────────────────────────────
# Install Nix
# ──────────────────────────────────────────────────────────────────────────────
install_nix_darwin() {
  msg "Installing Determinate Nix (macOS package)"
  local tmpdir pkg
  tmpdir="$(mktemp -d)"
  # Double-quote the trap so $tmpdir expands at trap-set time. With single
  # quotes, it expands at EXIT time — but $tmpdir is `local`, so it's already
  # unset by then and the pkg leaks in /tmp (~100MB).
  trap "rm -rf '$tmpdir'" EXIT
  pkg="$tmpdir/Determinate.pkg"
  curl --proto '=https' --tlsv1.2 -sSfL \
    https://install.determinate.systems/determinate-pkg/stable/Universal \
    -o "$pkg"
  if ! sudo installer -verboseR -pkg "$pkg" -target /; then
    warn "macOS .pkg installer failed — falling back to shell installer"
    curl --proto '=https' --tlsv1.2 -sSfL https://install.determinate.systems/nix | sh -s -- install
  fi
}

install_nix_linux_daemon() {
  msg "Installing Determinate Nix (Linux, daemon mode)"
  curl --proto '=https' --tlsv1.2 -sSfL https://install.determinate.systems/nix | sh -s -- install
}

write_linux_bootstrap() {
  # Home-manager writes ~/.zshrc, ~/.zshenv, etc. as symlinks into /nix/store,
  # which isn't visible at SSH login before the rootless-Nix sandbox is entered.
  # We write four small REAL files (not store symlinks) to bootstrap sandbox
  # entry whichever shell the user's login account uses:
  #   ~/.nix-bootstrap.sh  shared logic: locale fix + sandbox exec (POSIX)
  #   ~/.bash_profile      stub sourcing ~/.bashrc
  #   ~/.bashrc            system bashrc + host extras + nix-bootstrap
  #   ~/.zprofile          nix-bootstrap
  # Host-specific pre-sandbox env (e.g. Cerebras corp bashrc for non-interactive
  # ssh cmds) goes in ~/.bashrc.extra, materialized by a per-host HM activation.
  msg "Writing bootstrap (.nix-bootstrap.sh, .bash_profile, .bashrc, .zprofile)"

  # One-time backup of any pre-existing non-managed file before we stomp it
  for f in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.zprofile"; do
    if [[ -f "$f" && ! -L "$f" && ! -e "$f.before-nix" ]] \
      && ! grep -q 'dotfiles-nix install.sh' "$f" 2>/dev/null; then
      cp "$f" "$f.before-nix"
    fi
  done

  cat > "$HOME/.nix-bootstrap.sh" <<'EOF'
# Managed by dotfiles-nix install.sh. DO NOT EDIT — overwritten on re-install.
# Sourced by ~/.bashrc and ~/.zprofile on rootless-Nix hosts. Enters the Nix
# sandbox (nix-portable or nix-user-chroot, whichever is installed) and
# re-execs as an interactive zsh login shell. POSIX-compatible so both bash
# and zsh can source it.

# Locale fix — RHEL/Rocky ship /usr/lib/locale/en_US.utf8 (lowercase) but not
# en_US.UTF-8, so a default uppercase LANG causes ~240 wasted glibc probes
# per process. Fires unconditionally so even non-interactive shells benefit.
if [ -d /usr/lib/locale/en_US.utf8 ] && [ ! -d /usr/lib/locale/en_US.UTF-8 ]; then
  export LANG=en_US.utf8
fi

# Bail for non-interactive shells (scripts shouldn't re-exec into a sandbox).
case $- in *i*) ;; *) return 0 ;; esac
# Bail if already in the sandbox (guard prevents re-entry loops).
[ -n "${NIX_USER_CHROOT:-}${NP_ENTERED:-}" ] && return 0

# Prefer nix-portable — installed when AppArmor blocks user namespaces.
# Proot runtime works without CAP_SYS_ADMIN or userns, at a per-syscall cost.
if [ -x "$HOME/.local/bin/nix-portable" ]; then
  export NP_ENTERED=1 NP_RUNTIME=proot
  exec "$HOME/.local/bin/nix-portable" /usr/bin/env zsh -l
fi

# Fall back to nix-user-chroot (requires user namespaces).
if [ -x "$HOME/.local/bin/nix-user-chroot" ] && [ -d "$HOME/.nix" ]; then
  # Sweep stale /tmp/nix-chroot.* dirs from sessions killed uncleanly
  # (SIGKILL/OOM/SSH drop). nix-user-chroot's cleanup only runs on clean exit.
  # Single grep over all /proc/*/mountinfo is ~10x faster than a per-file loop.
  # Race-safe: skips dirs <5s old, skips dirs with live mount refs, owned-only.
  _live=$(grep -ohE '/tmp/nix-chroot\.[A-Za-z0-9]+' /proc/[0-9]*/mountinfo 2>/dev/null | sort -u)
  _now=$(date +%s 2>/dev/null)
  for _d in /tmp/nix-chroot.*; do
    [ -d "$_d" ] && [ -O "$_d" ] || continue
    _mt=$(stat -c %Y "$_d" 2>/dev/null) || continue
    [ $((_now - _mt)) -lt 5 ] && continue
    printf '%s\n' "$_live" | grep -qxF "$_d" && continue
    rm -rf -- "$_d" 2>/dev/null || true
  done
  unset _live _now _d _mt

  # Prepend nix profile to PATH so /usr/bin/env finds nix's zsh (patchelf'd
  # against nix's glibc) — the system zsh would fail to load plugin .so files
  # built against a newer glibc than the host ships.
  export NIX_USER_CHROOT=1
  export PATH="$HOME/.nix-profile/bin:$PATH"
  exec "$HOME/.local/bin/nix-user-chroot" "$HOME/.nix" /usr/bin/env zsh -l
fi
EOF

  cat > "$HOME/.bash_profile" <<'EOF'
# Managed by dotfiles-nix install.sh. DO NOT EDIT — overwritten on re-install.
[ -r "$HOME/.bashrc" ] && . "$HOME/.bashrc"
EOF

  cat > "$HOME/.bashrc" <<'EOF'
# Managed by dotfiles-nix install.sh. DO NOT EDIT — overwritten on re-install.
[ -f /etc/bashrc ] && . /etc/bashrc
[ -r "$HOME/.bashrc.extra" ] && . "$HOME/.bashrc.extra"
[ -r "$HOME/.nix-bootstrap.sh" ] && . "$HOME/.nix-bootstrap.sh"
EOF

  cat > "$HOME/.zprofile" <<'EOF'
# Managed by dotfiles-nix install.sh. DO NOT EDIT — overwritten on re-install.
[ -r "$HOME/.nix-bootstrap.sh" ] && . "$HOME/.nix-bootstrap.sh"
EOF
}

install_nix_linux_userns() {
  local arch chroot_url
  arch="$(uname -m)"
  chroot_url="https://github.com/nix-community/nix-user-chroot/releases/download/${NIX_USER_CHROOT_VERSION}/nix-user-chroot-bin-${NIX_USER_CHROOT_VERSION}-${arch}-unknown-linux-musl"

  mkdir -p "$(dirname "$NIX_USER_CHROOT")" "$NIX_ROOT"
  if [[ ! -x "$NIX_USER_CHROOT" ]]; then
    msg "Downloading nix-user-chroot ${NIX_USER_CHROOT_VERSION} (${arch})"
    # Download to .tmp first, then atomic rename, so an interrupted curl
    # never leaves a truncated-but-executable binary on disk.
    curl -sSfL "$chroot_url" -o "$NIX_USER_CHROOT.tmp"
    chmod +x "$NIX_USER_CHROOT.tmp"
    mv "$NIX_USER_CHROOT.tmp" "$NIX_USER_CHROOT"
  fi

  # Inside the chroot, /nix is bind-mounted to $HOME/.nix (writable by user).
  # Upstream Nix --no-daemon believes it's writing to /nix and succeeds.
  # Touch a sentinel at the end so interrupted runs get retried fully.
  if ! has_nix_rootless; then
    msg "Bootstrapping upstream Nix inside the chroot"
    "$NIX_USER_CHROOT" "$NIX_ROOT" bash -c '
      set -euo pipefail
      curl --proto "=https" --tlsv1.2 -sSfL https://nixos.org/nix/install | sh -s -- --no-daemon
      mkdir -p ~/.config/nix
      grep -qF "experimental-features" ~/.config/nix/nix.conf 2>/dev/null \
        || echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
    '
    touch "$NIX_ROOT/.install-complete"
  fi
}

install_nix_linux_portable() {
  # PRoot-based fallback for hosts where AppArmor blocks user namespaces
  # (Ubuntu 23.10+ default). Pays a 25-45% per-syscall cost but requires no
  # admin intervention. Binary caches still work — the bundled Nix 2.20.6
  # hits cache.nixos.org normally; the sandbox is transparent to HTTP.
  local arch portable_url
  arch="$(uname -m)"
  portable_url="https://github.com/DavHau/nix-portable/releases/download/${NIX_PORTABLE_VERSION}/nix-portable-${arch}"

  mkdir -p "$(dirname "$NIX_PORTABLE")"
  if [[ ! -x "$NIX_PORTABLE" ]]; then
    msg "Downloading nix-portable ${NIX_PORTABLE_VERSION} (${arch})"
    curl -sSfL "$portable_url" -o "$NIX_PORTABLE.tmp"
    chmod +x "$NIX_PORTABLE.tmp"
    mv "$NIX_PORTABLE.tmp" "$NIX_PORTABLE"
  fi

  # First invocation extracts ~100MB to $HOME/.nix-portable and caches the
  # runtime selection. Force proot up front so bwrap/nix probes don't waste
  # time failing against the AppArmor block.
  # Expect 60-120s on network-backed $HOME (e.g. CephFS); the first
  # home-manager switch that follows this is where most of the time goes.
  msg "Extracting nix-portable (first-run ~1-2 min on network-backed home)"
  NP_RUNTIME=proot "$NIX_PORTABLE" nix --version >/dev/null
}

install_nix_linux_rootless() {
  # Dispatch between nix-user-chroot (needs userns) and nix-portable (works
  # via PRoot without userns). Probe only `--user --mount -r` — that matches
  # what nix-user-chroot actually does (CLONE_NEWUSER | CLONE_NEWNS with uid
  # remap). Adding --pid --fork would false-negative on hardened kernels that
  # allow user+mount namespaces but not PID ones.
  if unshare --user --mount -r true 2>/dev/null; then
    msg "No sudo — installing Nix rootless via nix-user-chroot"
    install_nix_linux_userns
    return
  fi

  # Userns unavailable. Diagnose cause for the log, then try nix-portable.
  if [[ "$(cat /proc/sys/kernel/unprivileged_userns_clone 2>/dev/null)" != "1" ]]; then
    warn "kernel.unprivileged_userns_clone=0 (kernel-level userns restriction)"
  elif [[ "$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns 2>/dev/null)" == "1" ]]; then
    warn "AppArmor blocks userns (Ubuntu 23.10+ default). Falling back to nix-portable (PRoot)."
  else
    warn "Userns creation blocked (seccomp/selinux/capability policy?). Falling back to nix-portable."
  fi
  install_nix_linux_portable
}

if ! (has_nix_on_path || has_nix_daemon || has_nix_rootless || has_nix_portable); then
  if is_darwin; then
    install_nix_darwin
  elif can_sudo; then
    install_nix_linux_daemon
  else
    install_nix_linux_rootless
  fi
fi

# Linux: write real (non-store) bootstrap rcfiles so the user's login shell
# (bash or zsh) can enter the sandbox at SSH login. Idempotent.
if ! is_darwin; then
  write_linux_bootstrap
fi

# Source nix into this shell if not already on PATH (daemon installs only —
# rootless installs aren't reachable outside the chroot so we wrap later).
if ! has_nix_on_path && has_nix_daemon; then
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

# ──────────────────────────────────────────────────────────────────────────────
# Set up default flake location (macOS only)
# ──────────────────────────────────────────────────────────────────────────────
# nix-darwin (stateVersion >= 6) looks at /etc/nix-darwin by default,
# so `darwin-rebuild switch` works without --flake after first install
if is_darwin; then
  if [[ -e /etc/nix-darwin && ! -L /etc/nix-darwin ]]; then
    err "/etc/nix-darwin exists but is not a symlink — refusing to overwrite (could be a real directory from an older nix-darwin install)"
    exit 1
  fi
  if [[ ! -e /etc/nix-darwin ]] || [[ "$(readlink /etc/nix-darwin 2>/dev/null)" != "$DOTFILES" ]]; then
    msg "Linking $DOTFILES -> /etc/nix-darwin"
    sudo ln -snf "$DOTFILES" /etc/nix-darwin
  fi
fi

# ──────────────────────────────────────────────────────────────────────────────
# Build and activate
# ──────────────────────────────────────────────────────────────────────────────

# Unfree packages (claude-code) — belt-and-suspenders in case nixpkgs.config
# doesn't propagate through home-manager.useGlobalPkgs on first build
export NIXPKGS_ALLOW_UNFREE=1

if is_darwin; then
  hostname=$(scutil --get LocalHostName 2>/dev/null || true)
  if [[ -z "$hostname" ]]; then
    err "scutil --get LocalHostName returned empty — set it with: sudo scutil --set LocalHostName 'Jakes-MacBook'"
    exit 1
  fi

  # Validate hostname matches a known flake configuration
  if ! nix eval "$DOTFILES#darwinConfigurations.\"$hostname\"" --raw --apply 'x: "ok"' 2>/dev/null; then
    err "No darwinConfigurations.\"$hostname\" found in flake.nix"
    echo ""
    echo "  Your Mac's hostname is: $hostname"
    echo "  Available configurations:"
    nix eval "$DOTFILES#darwinConfigurations" --apply 'builtins.attrNames' 2>/dev/null || echo "    (could not list)"
    echo ""
    echo "  Either:"
    echo "    1. Add darwinConfigurations.\"$hostname\" to flake.nix"
    echo "    2. Or rename this Mac: sudo scutil --set LocalHostName 'Jakes-MacBook'"
    exit 1
  fi

  msg "Building nix-darwin configuration for $hostname"

  # First run: nix-darwin isn't installed yet, so use nix run to bootstrap
  if ! command -v darwin-rebuild >/dev/null 2>&1; then
    msg "Bootstrapping nix-darwin (first run)"
    sudo -H nix run nix-darwin/master#darwin-rebuild -- switch --flake "$DOTFILES#$hostname"
  else
    # Use command -v (shell built-in) to survive sudo PATH reset
    sudo -H "$(command -v darwin-rebuild)" switch --flake "$DOTFILES#$hostname"
  fi
else
  # Linux: home-manager with bare flake auto-resolves via $USER@$(hostname).
  # For hosts where hostname churns (UWaterloo student CS), set
  # REBUILD_FLAKE_ATTR in the env before running install.sh to target a
  # specific attr — e.g. `REBUILD_FLAKE_ATTR=jbedmons@uwaterloo ./install.sh`.
  # Subsequent rebuilds pick it up from home.sessionVariables automatically.
  msg "Building home-manager configuration"
  flake_target="$DOTFILES${REBUILD_FLAKE_ATTR:+#$REBUILD_FLAKE_ATTR}"
  # -b bak: back up pre-existing ~/.bashrc, ~/.zshrc etc. so home-manager
  # can take ownership without manual cleanup. Only pass on FIRST activation —
  # on re-runs a .bak already exists and HM would abort rather than overwrite.
  hm_args=( switch --flake "$flake_target" )
  if [[ ! -e "$HOME/.local/state/home-manager/gcroots/current-home" ]]; then
    hm_args+=( -b bak )
  fi
  if has_nix_on_path; then
    nix run home-manager/master -- "${hm_args[@]}"
  elif has_nix_portable; then
    # PRoot-based — nix-portable bind-mounts its internal store onto /nix,
    # so home-manager's hardcoded /nix/store paths resolve correctly inside.
    NP_RUNTIME=proot "$NIX_PORTABLE" nix run home-manager/master -- "${hm_args[@]}"
  else
    # User-namespace chroot — /nix is bind-mounted to $NIX_ROOT inside.
    "$NIX_USER_CHROOT" "$NIX_ROOT" bash -c "
      set -euo pipefail
      . \$HOME/.nix-profile/etc/profile.d/nix.sh
      nix run home-manager/master -- ${hm_args[*]@Q}
    "
  fi
fi

msg "Done! Open a new terminal session to pick up all changes."
