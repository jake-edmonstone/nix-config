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

is_darwin() { [[ "$(uname -s)" == "Darwin" ]]; }
# Can we become root without an interactive prompt?
can_sudo() { [[ "$EUID" -eq 0 ]] || sudo -n true 2>/dev/null; }

# Any of: daemon install on PATH, daemon install not on PATH yet, rootless install.
# Rootless uses a sentinel file so a half-downloaded / interrupted install
# doesn't claim completion just because a stray binary exists.
has_nix_on_path()  { command -v nix >/dev/null 2>&1; }
has_nix_daemon()   { [[ -x /nix/var/nix/profiles/default/bin/nix ]]; }
has_nix_rootless() { [[ -f "$NIX_ROOT/.install-complete" ]]; }

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

write_linux_bootstrap_bashrc() {
  # On rootless Nix, home-manager would write ~/.bashrc as a symlink into
  # /nix/store — which isn't accessible at SSH login before entering the
  # chroot. Instead, we write a small REAL ~/.bashrc + ~/.bash_profile that
  # do the chroot entry and then exec zsh. Host-specific extras (corporate
  # env files, custom PATH entries, etc.) get sourced from ~/.bashrc.extra
  # if present — a per-host home-manager module materializes that file.
  msg "Writing bootstrap ~/.bashrc and ~/.bash_profile"

  # One-time backup of any pre-existing system-default bashrc before we stomp it
  for f in "$HOME/.bashrc" "$HOME/.bash_profile"; do
    if [[ -f "$f" && ! -L "$f" && ! -e "$f.before-nix" ]] \
      && ! grep -q 'dotfiles-nix install.sh' "$f" 2>/dev/null; then
      cp "$f" "$f.before-nix"
    fi
  done

  cat > "$HOME/.bash_profile" <<'EOF'
# Managed by ~/dotfiles-nix install.sh. DO NOT EDIT — overwritten on rebuild.
[ -r ~/.bashrc ] && . ~/.bashrc
EOF

  cat > "$HOME/.bashrc" <<'EOF'
# Managed by ~/dotfiles-nix install.sh. DO NOT EDIT — overwritten on rebuild.
# Real file (not a /nix/store symlink) so bash can read it at SSH login,
# before nix-user-chroot is entered and /nix/store becomes accessible.

# Source system definitions
[ -f /etc/bashrc ] && . /etc/bashrc

# Host-specific extras, written as a real file by home-manager activation
[ -r "$HOME/.bashrc.extra" ] && . "$HOME/.bashrc.extra"

# Match the host glibc's locale dir name before zsh is exec'd. RHEL/Rocky
# ship /usr/lib/locale/en_US.utf8 (lowercase); the capitalized form doesn't
# exist, so every LC_* category causes a nonexistent-path probe on startup.
if [ -d /usr/lib/locale/en_US.utf8 ] && [ ! -d /usr/lib/locale/en_US.UTF-8 ]; then
  export LANG=en_US.utf8
fi

# Switch interactive shells to zsh, entering the nix-user-chroot if installed
# so zsh starts with /nix/store already visible. Prepend ~/.nix-profile/bin to
# PATH before exec so `env zsh` inside the chroot finds Nix's zsh (patchelf'd
# against Nix's glibc) — using the system zsh would fail to load plugin .so
# files built against a newer glibc than the host ships.
if [[ $- == *i* ]] && command -v zsh >/dev/null 2>&1; then
  if [ -x "$HOME/.local/bin/nix-user-chroot" ] && [ -d "$HOME/.nix" ] \
     && [ -z "${NIX_USER_CHROOT:-}" ]; then
    export NIX_USER_CHROOT=1
    export PATH="$HOME/.nix-profile/bin:$PATH"
    exec "$HOME/.local/bin/nix-user-chroot" "$HOME/.nix" /usr/bin/env zsh -l
  fi
  exec zsh -l
fi
EOF
}

install_nix_linux_rootless() {
  msg "No sudo available — installing Nix rootless via nix-user-chroot"

  if ! unshare --user --pid --mount --fork -r true 2>/dev/null; then
    err "Unprivileged user namespaces are disabled on this host — rootless install not possible"
    err "Ask the admin to enable user.max_user_namespaces, or use nix-portable for ad-hoc tools"
    exit 1
  fi

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

if ! (has_nix_on_path || has_nix_daemon || has_nix_rootless); then
  if is_darwin; then
    install_nix_darwin
  elif can_sudo; then
    install_nix_linux_daemon
  else
    install_nix_linux_rootless
  fi
fi

# Linux: write bootstrap bash files (real, not nix-store symlinks) so SSH
# login works before the chroot is entered. Idempotent — safe to re-run.
if ! is_darwin; then
  write_linux_bootstrap_bashrc
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
  # Add a new homeConfigurations."<user>@<host>" entry in flake.nix to register
  # additional machines.
  msg "Building home-manager configuration"
  # -b bak: back up any pre-existing ~/.bashrc, ~/.zshrc etc. so home-manager
  # can take ownership without manual cleanup. Only pass it on the FIRST
  # activation — on re-runs ~/.bashrc.bak already exists and HM would abort
  # rather than overwrite it.
  hm_args=( switch --flake "$DOTFILES" )
  if [[ ! -e "$HOME/.local/state/home-manager/gcroots/current-home" ]]; then
    hm_args+=( -b bak )
  fi
  if has_nix_on_path; then
    nix run home-manager/master -- "${hm_args[@]}"
  else
    # Rootless — run through nix-user-chroot so /nix/store is visible
    "$NIX_USER_CHROOT" "$NIX_ROOT" bash -c "
      set -euo pipefail
      . \$HOME/.nix-profile/etc/profile.d/nix.sh
      nix run home-manager/master -- ${hm_args[*]@Q}
    "
  fi
fi

msg "Done! Open a new terminal session to pick up all changes."
