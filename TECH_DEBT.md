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

## Rex Timewarrior status integration

**Status:** Blocked by missing custom status-widget support in Rex as of
2026-11-07.

The former tmux status line displayed the active Timewarrior tag and current
interval duration, refreshed every five seconds. The native Rex
setup has no equivalent persistent status display. Rex's program-status
protocol is not a general-purpose replacement for a configurable status bar.

- Upstream: [UI Modification Hooks](https://discord.com/channels/1546797889009881158/1567573986416656404),
  an active request for custom status text, colors, and Lua-driven UI modules.
- No workaround is installed: avoid nesting tmux solely for its status line
  or dedicating a Rex pane to a timer. The tmux module and its status helper
  have been removed as part of the migration to Rex; Timewarrior remains installed.
- Revisit when Rex supports custom status widgets. Add a native display of
  the active tag and elapsed time, with no idle polling when practical, then
  remove this entry after verifying start/stop updates and refresh cost.

## Rex keyboard copy mode

**Status:** Native vi-style copy mode is an accepted feature request, not yet
shipped as of 2026-11-07.

Rex cannot currently replace tmux's keyboard-driven scrollback navigation,
selection, and copying. The tmux configuration has been removed, so this is a
known workflow gap in the native Rex setup.

- Upstream: [terminal vi copy mode support](https://discord.com/channels/1546797889009881158/1558373508117958686).
- No workaround is installed. Community scripts open `rex capture` output in
  a floating Neovim pane, but this is a snapshot, not native copy mode; for
  alternate-screen applications it contains only the visible screen.
- Revisit when native support ships. Configure an entry shortcut and verify
  keyboard scrolling, selection, clipboard copying, and cancellation in both
  shell scrollback and fullscreen programs before removing this entry.

## Rex tab-number hints with Ctrl-B

**Status:** Tracking an upstream feature request as of 2026-11-07; no local
workaround or code change is needed now.

Holding Cmd reveals Rex's tab-number hints, but they do not appear while a
tmux-style key sequence is pending. Our Ctrl-B then 1-9 bindings select tabs
through `client.tab.goto`, so it would be useful to see the corresponding
numbers immediately after pressing Ctrl-B.

- Upstream: [Consistent tab numbering](https://discord.com/channels/1546797889009881158/1566437212436955156),
  which requests showing the number legend while a key sequence is pending.
- Check future Rex updates for this behavior. Verify that Ctrl-B reveals
  the hints and that their numbers match Ctrl-B then 1-9 in the active tab
  layout. Enable a native option if required, then remove this entry.
