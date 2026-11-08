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

## Neovim nightly for watcher-backed autoread and multicursors

**Status:** Waiting for both watcher-backed autoread and native multicursor
support to reach the nixpkgs Neovim package.

Neovim nightly is used so `autoread` notices external edits through file-system
watchers without custom polling autocommands. The configuration also relies on
native multicursors (the `Q` workflow and `nvim.multicursor` namespace used by
the Ctrl-L clearing binding). Both features must be available before leaving
nightly, including when evaluating Neovim 0.13 as a replacement.

As of 2026-09-07, nixpkgs unstable packages Neovim 0.12.5. Its release branch
does not contain the watcher commit, so the nightly override is still required.

- Upstream: [neovim/neovim#37971](https://github.com/neovim/neovim/pull/37971)
- Temporary code:
  - `flake.nix`: the `neovim-nightly-overlay` input and Darwin package override.
  - `config/nvim/lua/config/autocmds.lua`: the commented pre-watcher fallback.
  - `config/nvim/lua/config/options.lua`: the `autoread` dependency note.
- Once nixpkgs Neovim contains both features, verify external-edit autoread
  and native multicursor creation/clearing with the existing Neovim tests.
  Then remove the nightly input, output
  argument, and package override; delete the commented fallback and its `TODO`.
  Keep `vim.o.autoread = true`, but remove its nightly-specific comment.

## Snacks image detection in Rex

**Status:** Temporary detection override added on 2026-11-08; no Rex-specific
Snacks issue or PR was found when checked that day.

Snacks' supported-terminal table does not include Rex, so it reports missing
Kitty graphics support and cannot select inline Unicode-placeholder rendering.
Rex supports both capabilities: [maintainer confirmation](https://discord.com/channels/1546797889009881158/1565841234893733959).
A separate [large-image rendering bug](https://discord.com/channels/1546797889009881158/1567145399859544156)
was marked completed on 2026-11-03.

- Temporary code: the Snacks plugin `init` in
  `config/nvim/lua/plugins/editor.lua` sets `SNACKS_GHOSTTY=true` only when
  `TERM_PROGRAM=rex`. This is the
  [documented environment-detection override](https://github.com/folke/snacks.nvim/blob/main/docs/image.md),
  applied inside Neovim, not a global change to terminal identity. It selects
  both graphics and placeholder support; `image.force` alone would not enable
  inline rendering.
- The health check also unconditionally looks for a `kitty`, `wezterm`, or
  `ghostty` executable. That error can remain despite working images; do not
  install an unused terminal just to silence it. Detection will report Ghostty
  while the override is active.
- Upstream: [Snacks terminal detection](https://github.com/folke/snacks.nvim/blob/main/lua/snacks/image/terminal.lua).
- Once the installed Snacks version recognizes Rex natively, remove the
  override and its `TODO`. Restart Neovim in Rex and verify `:checkhealth snacks`,
  an image-file preview, and inline images before removing this entry.

## Codex diff colors leaking in Rex

**Status:** Tracking visual corruption as of 2026-11-08; related Rex reports
remain active, with no confirmed fix or local workaround. Terminal-owned
scrollback remains preferred despite the visual issue.

Codex's red/green diff highlighting sometimes appears on unrelated content.
A Rex report describes Codex colors changing after scrolling; two others
describe tool-output backgrounds spreading beyond their intended blocks in Pi.
These suggest a terminal rendering/state issue, but do not establish whether
our symptom originates in Rex, its underlying terminal engine, or Codex.

- Upstream: [Incorrect coloring behavior in Codex](https://discord.com/channels/1546797889009881158/1564380403790520320)
  (2026-10-26).
- Related: [Pi tool background color bleeds across entire terminal pane](https://discord.com/channels/1546797889009881158/1568083488488558632)
  (2026-11-06), and [Terminal background colors bleed into the entire viewport](https://discord.com/channels/1546797889009881158/1565286750769647647)
  (2026-10-29). These are similar symptoms in another application, not confirmed
  duplicates of the Codex issue.
- No configuration workaround is installed. Keep
  `programs.codex.settings.tui.alternate_screen = "never"` in
  `modules/codex.nix` for terminal-owned scrollback. This is unrelated to the
  Neovim-only Snacks detection override above.
- Revisit these reports and Rex/Codex release notes for a confirmed fix.
  Verify diff colors stay confined to the correct lines while generating,
  scrolling, and resizing with terminal-owned scrollback before removing
  this entry. No scrollback configuration change is needed on resolution.

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
