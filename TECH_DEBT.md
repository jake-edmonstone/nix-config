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

## Rex scrollback restoration and agent resumption

**Status:** Tracking missing native recovery features as of 2026-11-08.
Agent resumption has a maintainer-confirmed plan, but no announced release date;
scrollback restoration is requested, not confirmed as scheduled.

Rex already restores sessions, tabs, splits, names, IDs, and working directories
after a server restart, as shipped in
[preview.23 on 2026-10-29](https://discord.com/channels/1546797889009881158/1547349572299395172/1565448157691777055).
Terminals return as fresh shells: their previous scrollback and running programs
are not restored, and agent conversations are not automatically resumed.

- Scrollback: [Restore sessions after a server restart](https://discord.com/channels/1546797889009881158/1565461187422846977)
  explicitly requests saving previous terminal output. Its layout portion has
  shipped; that does not mean scrollback restoration has shipped too.
- Agent resumption: [Native Coding Agent Lifecycle Tracking and Crash/Restart Auto-Resume](https://discord.com/channels/1546797889009881158/1565927087624429599).
  On 2026-10-31, Mitchell confirmed there is a plan. This would launch agents
  against saved conversations, not recover arbitrary interrupted computation.
- Related: [Layout restore discussion](https://discord.com/channels/1546797889009881158/1565463064038604908)
  includes community proposals for live server upgrades that preserve terminal
  connections and running processes. This is distinct from restoring after a
  reboot; it is not confirmed as implemented in Rex.
- No local recovery scripts are installed. Keep the server running to preserve
  live work; closing the GUI alone does not require restoration.
- Revisit Rex release notes and these discussions for native support. Test in
  a disposable session that scrollback survives a server restart and Codex
  resumes the correct saved conversation in its original pane and directory.
  Do not test by stopping the server while unrelated work is running. Resolve
  each missing capability independently; remove this entry when both work.

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

## Rex tab-number hints and toolbar reveal with Ctrl-B

**Status:** Rechecked on 2026-11-17. Prefix-triggered tab-number hints remain
an active feature request; no native prefix-triggered toolbar reveal setting
was found. No local workaround is installed.

Holding Cmd reveals Rex's tab-number hints, but they do not appear while a
tmux-style key sequence is pending. Our Ctrl-B then 1-9 bindings select tabs
through `client.tab.goto`, so it would be useful to see the corresponding
numbers immediately after pressing Ctrl-B.
When the toolbar is set to Show on hover, pressing Ctrl-B should also reveal
it so those numbers and tabs are visible without moving the pointer.

- Upstream: [Consistent tab numbering](https://discord.com/channels/1546797889009881158/1566437212436955156),
  which requests showing the number legend while a key sequence is pending.
- Related: [Extend hold key number hints for windows](https://discord.com/channels/1546797889009881158/1561730133327618088)
  also discusses custom modifiers and prefix-based tab navigation.
- [Show key sequence hints](https://www.superlogical.com/rex/docs/reference/mac-settings#keyboard)
  lists possible next keys in a separate overlay; it is not a substitute for
  numbers on the actual tabs. [Reveal Toolbar](https://www.superlogical.com/rex/docs/reference/mac-actions#action-client-toolbar-reveal)
  (`client.toolbar.reveal`, normally Cmd-Option-T) can reveal an auto-hidden
  toolbar manually. No dedicated upstream request for revealing it on prefix
  was found; the linked numbering requests do not establish that it is planned.
- Check future Rex updates for this behavior. Verify that Ctrl-B reveals
  the toolbar in Show on hover mode and displays tab-number hints matching
  Ctrl-B then 1-9 in the active tab layout. Check that the toolbar hides again
  after completing or cancelling the sequence. Enable native options if
  required, and resolve the two capabilities independently before removing
  this entry.
