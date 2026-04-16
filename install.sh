#!/usr/bin/env bash
set -euo pipefail

msg()  { printf "\033[1;32m==>\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33mWARNING:\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31mERROR:\033[0m %s\n" "$*" >&2; }

DOTFILES="$(cd "$(dirname "$0")" && pwd)"

# ──────────────────────────────────────────────────────────────────────────────
# macOS prerequisites
# ──────────────────────────────────────────────────────────────────────────────
if [[ "$(uname -s)" == "Darwin" ]]; then
  # Xcode Command Line Tools
  if ! xcode-select -p >/dev/null 2>&1; then
    msg "Installing Xcode Command Line Tools"
    xcode-select --install
    echo "Finish the CLT install in the popup, then re-run this script."
    exit 0
  fi

  # Rosetta 2 (Apple Silicon)
  if [[ "$(uname -m)" == "arm64" ]] && ! /usr/bin/pgrep oahd >/dev/null 2>&1; then
    msg "Installing Rosetta 2"
    softwareupdate --install-rosetta --agree-to-license
  fi
fi

# ──────────────────────────────────────────────────────────────────────────────
# Install Nix (Determinate Nix — native macOS package, shell installer on Linux)
# ──────────────────────────────────────────────────────────────────────────────
if ! command -v nix >/dev/null 2>&1; then
  if [[ "$(uname -s)" == "Darwin" ]]; then
    msg "Installing Determinate Nix (macOS package)"
    _pkg="$(mktemp -d)/Determinate.pkg"
    curl --proto '=https' --tlsv1.2 -sSfL \
      https://install.determinate.systems/determinate-pkg/stable/Universal \
      -o "$_pkg"
    sudo installer -verboseR -pkg "$_pkg" -target /
    rm -f "$_pkg"
  else
    msg "Installing Nix (Determinate Systems installer)"
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
  fi
  # Source nix in this shell
  if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  fi
fi

# ──────────────────────────────────────────────────────────────────────────────
# Set up default flake location
# ──────────────────────────────────────────────────────────────────────────────
# nix-darwin (stateVersion >= 6) looks at /etc/nix-darwin by default,
# so `darwin-rebuild switch` works without --flake after first install
if [[ "$(uname -s)" == "Darwin" ]]; then
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

if [[ "$(uname -s)" == "Darwin" ]]; then
  HOSTNAME=$(scutil --get LocalHostName)

  # Validate hostname matches a known flake configuration
  if ! nix eval "$DOTFILES#darwinConfigurations.\"$HOSTNAME\"" --raw --apply 'x: "ok"' 2>/dev/null; then
    err "No darwinConfigurations.\"$HOSTNAME\" found in flake.nix"
    echo ""
    echo "  Your Mac's hostname is: $HOSTNAME"
    echo "  Available configurations:"
    nix eval "$DOTFILES#darwinConfigurations" --apply 'builtins.attrNames' 2>/dev/null || echo "    (could not list)"
    echo ""
    echo "  Either:"
    echo "    1. Add darwinConfigurations.\"$HOSTNAME\" to flake.nix"
    echo "    2. Or rename this Mac: sudo scutil --set LocalHostName 'Jakes-MacBook'"
    exit 1
  fi

  msg "Building nix-darwin configuration for $HOSTNAME"

  # First run: nix-darwin isn't installed yet, so use nix run to bootstrap
  if ! command -v darwin-rebuild >/dev/null 2>&1; then
    msg "Bootstrapping nix-darwin (first run)"
    nix run nix-darwin/master#darwin-rebuild -- switch --flake "$DOTFILES#$HOSTNAME"
  else
    # Use $(which ...) to survive sudo PATH reset
    sudo "$(which darwin-rebuild)" switch --flake "$DOTFILES#$HOSTNAME"
  fi
else
  msg "Building home-manager configuration"
  # Standalone home-manager for Linux (e.g. Cerebras)
  nix run home-manager/master -- switch --flake "$DOTFILES#cerebras"
fi

msg "Done! Open a new terminal session to pick up all changes."
