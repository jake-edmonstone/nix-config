# Technical Debt

Temporary workarounds and blocked updates in this configuration. Keep the
corresponding `TODO` comments in the code until each item is resolved.

## Nix MCP server dependency compatibility

**Status:** Application-scoped workaround verified on macOS on 2026-10-24:
full configuration evaluation, package build, MCP initialization, and tool discovery passed.

The locked nixpkgs revision selects MCP SDK 2.x, but FastMCP 3.4.7 requires
MCP 1.x. Consequently, `fastmcp-slim` is marked broken and prevents evaluation
of the configuration through `programs.mcp.servers.nixos.command`.

- Temporary code: `mcpNixos` in `modules/codex.nix` uses nixpkgs' `mcp_1`
  within a Python package scope used only by `mcp-nixos`. The global Python
  environment is unchanged; broken-package checks remain enabled.
- Upstream: [nixpkgs#563493: update FastMCP to 4.0.10](https://github.com/NixOS/nixpkgs/pull/563493).
  [nixpkgs#577109](https://github.com/NixOS/nixpkgs/pull/577109) discusses the
  MCP 1.x workaround and the risks of mixing SDK versions in a shared scope.
- Once the locked nixpkgs package works without the override, remove
  `mcpNixos` and its `TODO`, restore `${pkgs.mcp-nixos}/bin/mcp-nixos` as the
  server command, and verify MCP startup/tool discovery before removing this entry.

## Sioyek macOS packaging

**Status:** Local workaround verified on macOS 27.0.1 on 2026-10-04; waiting
for nixpkgs packaging fixes.

The installed `2.0.0-unstable-2026-08-18` package puts shaders, default configs,
and the tutorial in `Contents/MacOS`, but its source reads them from
`Contents/Resources`. Missing shaders leave PDF pages blank. The current nixpkgs
[package recipe](https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/si/sioyek/package.nix)
still uses the old location.

Upstream fix: [nixpkgs#566097: install Darwin resources into Contents/Resources](https://github.com/NixOS/nixpkgs/pull/566097).
This PR fixes the blank pages, but does not change executable wrapping. Once it
lands in the locked nixpkgs revision, remove the resource-moving step; retain
the unwrapped executable and `qt.conf` workaround until the PID/hiding issue is
also resolved.

The copied app's Qt executable wrapper also leaves AppKit reporting its PID as
`-1`, so Hammerspoon cannot manage it normally. A temporary copy with the native
executable and corrected resources rendered the tutorial and hid correctly
when switching apps with Hyper.

- Temporary code: `programs.sioyek.package`, `qtRuntime`, and `qtConf` in
  `modules/sioyek.nix`.
- Move the resources into their expected directory and use Qt's supported
  [qt.conf](https://doc.qt.io/qt-6/qt-conf.html) for plugin/QML paths instead of
  wrapping the app executable. Hammerspoon needs no special-case workaround.
- Remove the override and Qt configuration helpers when the stock nixpkgs
  package renders PDFs and exposes a valid application PID. Test both opening
  from Finder/Hyper-P and hiding when switching to another app.

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

**Status:** Stock tmux 3.8 trial prepared on 2026-10-24. The locked nixpkgs
contains 3.8 and its isolated navigation/configuration tests pass. Interactive
Ghostty verification during Codex streaming is still required; the existing
tmux server has not been restarted.

tmux 3.7 through 3.7c corrupts or repeatedly redraws the title border of tmux
popups while Codex is streaming output. The configuration previously pinned
tmux 3.6b, a maintenance release from the unaffected 3.6 series. This matches
[tmux#5336](https://github.com/tmux/tmux/issues/5336): scrolling or full-region
redraws in a pane behind `display-popup` unnecessarily repaint the popup.

- Trial code: `flake.nix` now uses stock nixpkgs tmux, with a `TODO` pending
  visual verification. Neither flake inputs nor the Neovim pin were updated.
- Upstream fix:
  [tmux@824a072](https://github.com/tmux/tmux/commit/824a07290f853a97219ee2624a46c0aada246efb),
  developed through [tmux#5398](https://github.com/tmux/tmux/pull/5398).
- tmux 3.7c does not contain the fix; 3.8 does. Removing the pin makes the next
  rebuild install 3.8, but does not replace an already-running 3.6b server.
- After rebuilding, coordinate a server migration without killing active work.
  First test an isolated 3.8 server with the usual config and session picker
  while Codex streams. Check the title border, clipping, flicker and navigation
  responsiveness. Only retire this entry and its `TODO` after the visual test
  passes on the normal setup.
- If the issue recurs, restore the previous `tmuxOverlay` from Git history
  (tag `3.6b`, source hash `sha256-iW4K/OxSVpxVkyI5Dy6lzwVf/8nXyjcHtL76Ezmxavc=`)
  and retain this entry with the test result. Navigation detection is independent
  of the version trial and should remain process-based.
