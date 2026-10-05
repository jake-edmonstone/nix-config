#!/usr/bin/env bash
set -euo pipefail

msg() { printf "\033[1;32m==>\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33mWARNING:\033[0m %s\n" "$*"; }
err() { printf "\033[1;31mERROR:\033[0m %s\n" "$*" >&2; }

DOTFILES="$(cd "$(dirname "$0")" && pwd)"
DARWIN_ATTR="Jakes-MacBook"
EXPECTED_USER="jbedm"
EXPECTED_DOTFILES="/Users/$EXPECTED_USER/nix-config"
DETERMINATE_TEAM_ID="X3JQ4VPJZ6"

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

if [[ "$DOTFILES" != "$EXPECTED_DOTFILES" ]]; then
  err "This configuration must be cloned to '$EXPECTED_DOTFILES'"
  err "Current checkout: '$DOTFILES'"
  exit 1
fi

# Homebrew requires the Command Line Tools for a supported macOS setup.
if ! xcode-select -p >/dev/null 2>&1; then
  msg "Installing Xcode Command Line Tools"
  xcode-select --install
  echo "Finish the CLT install in the popup, then re-run this script."
  exit 0
fi

if command -v nix >/dev/null 2>&1; then
  NIX_BIN="$(command -v nix)"
elif [[ -x /nix/var/nix/profiles/default/bin/nix ]]; then
  NIX_BIN="/nix/var/nix/profiles/default/bin/nix"
else
  NIX_BIN=""
fi
nix_version="$(${NIX_BIN:-false} --version 2>/dev/null || true)"

if [[ "$nix_version" != *"Determinate Nix"* ]]; then
  if [[ -n "$nix_version" ]]; then
    msg "Migrating the existing Nix installation to Determinate Nix"
  else
    msg "Installing Determinate Nix"
  fi

  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT
  pkg="$tmpdir/Determinate.pkg"
  curl --proto '=https' --tlsv1.2 -sSfL \
    https://install.determinate.systems/determinate-pkg/stable/Universal \
    -o "$pkg"

  signature="$(spctl -a -vv -t install "$pkg" 2>&1 || true)"
  actual_team_id="$(printf '%s\n' "$signature" | awk -F '(' '/origin=/ { print $2 }' | tr -d '()')"
  if [[ "$actual_team_id" != "$DETERMINATE_TEAM_ID" ]]; then
    err "Determinate package signature did not match the expected developer"
    err "Expected Team ID: $DETERMINATE_TEAM_ID"
    err "Actual Team ID: ${actual_team_id:-unknown}"
    exit 1
  fi

  sudo installer -verboseR -pkg "$pkg" -target /
fi

if [[ -x /nix/var/nix/profiles/default/bin/nix ]]; then
  NIX_BIN="/nix/var/nix/profiles/default/bin/nix"
elif command -v nix >/dev/null 2>&1; then
  NIX_BIN="$(command -v nix)"
else
  NIX_BIN=""
fi

if [[ -z "$NIX_BIN" ]]; then
  err "Determinate Nix was installed, but 'nix' is not available"
  err "Open a new terminal and re-run this script"
  exit 1
fi

if [[ "$($NIX_BIN --version 2>/dev/null || true)" != *"Determinate Nix"* ]]; then
  err "This configuration requires Determinate Nix"
  err "Detected: $($NIX_BIN --version 2>/dev/null || echo unknown)"
  exit 1
fi

if ! command -v darwin-rebuild >/dev/null 2>&1; then
  warn "This configuration installs applications from the Mac App Store."
  warn "Sign into the App Store app before continuing; iCloud sign-in alone is not sufficient."
  printf "Press Return once the App Store shows your account, or Ctrl-C to stop: "
  read -r
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

msg "Building nix-darwin configuration for $DARWIN_ATTR"

if ! command -v darwin-rebuild >/dev/null 2>&1; then
  msg "Bootstrapping nix-darwin"
  sudo -H "$NIX_BIN" run "$DOTFILES#darwin-rebuild" -- \
    switch --flake "$DOTFILES#$DARWIN_ATTR"
else
  sudo -H "$(command -v darwin-rebuild)" \
    switch --flake "$DOTFILES#$DARWIN_ATTR"
fi

msg "Done! Open a new terminal session to pick up all changes."
