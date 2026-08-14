#!/usr/bin/env bash
set -euo pipefail

msg() { printf "\033[1;32m==>\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33mWARNING:\033[0m %s\n" "$*"; }
err() { printf "\033[1;31mERROR:\033[0m %s\n" "$*" >&2; }

DOTFILES="$(cd "$(dirname "$0")" && pwd)"
DARWIN_ATTR="Jakes-MacBook"
EXPECTED_USER="jbedm"

if [[ "$(uname -s)" != "Darwin" ]]; then
  err "install.sh only supports macOS"
  exit 1
fi

if [[ "$(uname -m)" != "arm64" ]]; then
  err "This configuration requires an Apple silicon Mac"
  exit 1
fi

if [[ "$(id -un)" != "$EXPECTED_USER" ]]; then
  err "This configuration requires the macOS account name '$EXPECTED_USER'"
  exit 1
fi

# Homebrew requires the Command Line Tools for a supported macOS setup.
if ! xcode-select -p >/dev/null 2>&1; then
  msg "Installing Xcode Command Line Tools"
  xcode-select --install
  echo "Finish the CLT install in the popup, then re-run this script."
  exit 0
fi

if ! command -v nix >/dev/null 2>&1 \
  && [[ ! -x /nix/var/nix/profiles/default/bin/nix ]]; then
  msg "Installing Determinate Nix"
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT
  pkg="$tmpdir/Determinate.pkg"
  curl --proto '=https' --tlsv1.2 -sSfL \
    https://install.determinate.systems/determinate-pkg/stable/Universal \
    -o "$pkg"
  if ! sudo installer -verboseR -pkg "$pkg" -target /; then
    warn "macOS package installer failed; falling back to the shell installer"
    curl --proto '=https' --tlsv1.2 -sSfL \
      https://install.determinate.systems/nix | sh -s -- install
  fi
fi

if ! command -v nix >/dev/null 2>&1; then
  set +u
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  set -u
fi

if [[ -e /etc/nix-darwin && ! -L /etc/nix-darwin ]]; then
  err "/etc/nix-darwin exists but is not a symlink; refusing to overwrite it"
  exit 1
fi
if [[ ! -e /etc/nix-darwin ]] \
  || [[ "$(readlink /etc/nix-darwin 2>/dev/null)" != "$DOTFILES" ]]; then
  msg "Linking $DOTFILES -> /etc/nix-darwin"
  sudo ln -snf "$DOTFILES" /etc/nix-darwin
fi

if [[ "$(scutil --get LocalHostName 2>/dev/null || true)" != "$DARWIN_ATTR" ]]; then
  msg "Setting LocalHostName to $DARWIN_ATTR"
  sudo scutil --set LocalHostName "$DARWIN_ATTR"
fi

if ! nix eval "$DOTFILES#darwinConfigurations.\"$DARWIN_ATTR\"" \
  --raw --apply 'x: "ok"' >/dev/null 2>&1; then
  err "No darwinConfigurations.\"$DARWIN_ATTR\" found in flake.nix"
  echo "Available configurations:"
  nix eval "$DOTFILES#darwinConfigurations" --apply builtins.attrNames 2>/dev/null \
    || echo "  (could not list configurations)"
  exit 1
fi

msg "Building nix-darwin configuration for $DARWIN_ATTR"

if ! command -v darwin-rebuild >/dev/null 2>&1; then
  msg "Bootstrapping nix-darwin"
  sudo -H nix run nix-darwin/master#darwin-rebuild -- \
    switch --flake "$DOTFILES#$DARWIN_ATTR"
else
  sudo -H "$(command -v darwin-rebuild)" \
    switch --flake "$DOTFILES#$DARWIN_ATTR"
fi

msg "Done! Open a new terminal session to pick up all changes."
