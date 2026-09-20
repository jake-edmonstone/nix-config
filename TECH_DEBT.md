# Technical Debt

Temporary workarounds and blocked updates in this configuration. Keep the
corresponding `TODO` comments in the code until each item is resolved.

## Determinate Nix creates project-local Sentry caches

**Status:** Upstream issue open as of 2026-09-19; explicitly disable the CLI's
Sentry endpoint as well as the daemon's.

Root-owned `.cache/nix/sentry` directories recur in project directories.
[DeterminateSystems/nix-src#626](https://github.com/DeterminateSystems/nix-src/issues/626)
reports the same problem with missing or empty home-directory environment data.
On this machine, `telemetry.sentry.endpoint = null` was applied in
`/etc/determinate/config.json`, but `/etc/nix/sentry-endpoint` still held a live
endpoint. The CLI reads the latter directly; an empty file skips Sentry setup.

- Temporary code: `environment.etc."nix/sentry-endpoint"` in
  `hosts/darwin/default.nix`.
- First activation requires moving the existing unmanaged endpoint file to
  `/etc/nix/sentry-endpoint.before-nix-darwin`.
- After a Determinate installer/upgrade, verify the endpoint remains empty;
  the installer may replace files it originally owned. Reapply the configuration
  if necessary. This is a declarative workaround, not an upstream fix.
- Remove the workaround once the daemon opt-out reliably disables CLI Sentry
  too. Confirm with a rebuild from a directory without an existing `.cache`.

## Neovim nightly for watcher-backed autoread

**Status:** Waiting for the required Neovim commit to reach the nixpkgs Neovim
package.

Neovim nightly is used so `autoread` notices external edits through file-system
watchers without custom polling autocommands.

As of 2026-09-07, nixpkgs unstable packages Neovim 0.12.5. Its release branch
does not contain the watcher commit, so the nightly override is still required.

- Upstream: [neovim/neovim#37971](https://github.com/neovim/neovim/pull/37971)
- Temporary code:
  - `flake.nix`: the `neovim-nightly-overlay` input and Darwin package override.
  - `config/nvim/lua/config/autocmds.lua`: the commented pre-watcher fallback.
  - `config/nvim/lua/config/options.lua`: the `autoread` dependency note.
- Once nixpkgs Neovim contains the change, remove the nightly input, output
  argument, and package override; delete the commented fallback and its `TODO`.
  Keep `vim.o.autoread = true`, but remove its nightly-specific comment.

## tmux 3.7 popup redraw regression

**Status:** Fixed on tmux `master`; waiting for a release containing the fix to
reach nixpkgs.

tmux 3.7 through 3.7c corrupts or repeatedly redraws the title border of tmux
popups while Codex is streaming output. The configuration therefore pins tmux
3.6b, the latest maintenance release from the unaffected 3.6 series. This matches
[tmux#5336](https://github.com/tmux/tmux/issues/5336): scrolling or full-region
redraws in a pane behind `display-popup` unnecessarily repaint the popup.

- Temporary code: `tmuxOverlay` in `flake.nix`.
- Upstream fix:
  [tmux@824a072](https://github.com/tmux/tmux/commit/824a07290f853a97219ee2624a46c0aada246efb),
  developed through [tmux#5398](https://github.com/tmux/tmux/pull/5398).
- tmux 3.7c was released on 2026-08-17, but does not contain the fix. Its
  `screen_redraw_update()` still marks an existing overlay for repaint on every
  redraw, and neither its commit range nor `CHANGES` includes the master fix.
  As of 2026-09-07, nixpkgs unstable packages 3.7c, so updating nixpkgs does not
  remove the need for the 3.6b pin.
- When nixpkgs ships a tmux release containing the fix, remove the overlay,
  rebuild, restart the tmux server, and test the session picker while Codex is
  actively generating text. Keep the pin if the popup title still flickers or
  is cut off.

## nix-homebrew auto-update breaks MAS activation

**Status:** Waiting for nix-homebrew to preserve `HOMEBREW_PATH` across
Homebrew's auto-update re-exec.

With activation auto-update enabled, the nix-homebrew wrapper re-executes Brew
with its filtered `PATH`. `brew bundle` then cannot find `mas`, even when it is
already installed, and every declarative Mac App Store entry fails. Cask and
MAS app upgrades still run because `homebrew.onActivation.upgrade` remains
enabled; the Homebrew executable is updated through the `nix-homebrew` flake
input.

- Upstream reports:
  [nix-homebrew#131](https://github.com/zhaofengli/nix-homebrew/issues/131) and
  [nix-homebrew#149](https://github.com/zhaofengli/nix-homebrew/issues/149).
- Temporary code: `homebrew.onActivation.autoUpdate = false` in
  `hosts/darwin/default.nix`.
- Once the wrapper preserves the original path across re-exec, set
  `autoUpdate` back to `true` and verify a rebuild recognizes the existing MAS
  apps.
