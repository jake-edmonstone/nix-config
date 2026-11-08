# Rex

Rex is the primary terminal and session manager. Hyper-T focuses Rex; Hyper-N
places Rex beside Helium in a 60/40 split. Ghostty and tmux are no longer
installed by this configuration.

## Apply

Run `nh darwin switch`, then `rex config check` and `rex config reload`.
Rex does not watch init.lua. Restart Neovim after switching; appearance
preferences may require quitting and reopening the Rex app. Do not stop its
server: that ends running programs.

The official beta installer/updater owns the app and bundled server. Home
Manager links its Current CLI and deploys config and generated theme files.
No additional Rex server is installed.

## Appearance

Import `~/.config/rex/themes/Dracula` and
`~/.config/rex/themes/Catppuccin Latte` in Settings > Themes. Select them for
dark and light mode respectively. The palette files follow theme.nix; reimport
after changing their colors. Importing creates app-owned custom themes, so it
is deliberately not repeated automatically on every activation.

Appearance defaults currently cover the UI-selected blendTheme material,
compact panes, hidden pane headers, Maple Mono NF at 18pt, 8% additional cell height,
application-controlled cursor shape and the experimental Warp trail.
They also preserve copy-on-selection, rounded selections, smooth scrolling,
pane glass disabled, and permission for agents to name new sessions. Agent
naming changes apply to new agent sessions, not existing ones.
Check these in Settings after switching. The trail is not the custom Ghostty
GLSL shader. Disable it in modules/rex.nix if it feels slow, especially in Low
Power Mode, or causes sustained idle CPU use.

Set these remaining UI preferences manually (their stored enum values have
not been verified, so Nix does not guess them):

- Interface > Tabs: Above.
- Terminal > Keyboard: Option sends Alt.
- Terminal > Cursor: Normal blink speed; do not force cursor style.
- Interface > Pane Padding: small vertical padding, approximately 3 points.
- Choose the same light/dark appearance as theme.nix.

Opacity/blur, hidden titlebar, and Maple Mono's cv01 feature are not claimed
to match Ghostty. Truecolor application output is not remapped.

Rex forces pane headers on when the sidebar is hidden; floating panes may
also ignore the setting. Keep the sidebar visible for headerless regular
panes. Compact styling reduces spacing, but does not remove the outer frame.
See the [pane-header discussion](https://discord.com/channels/1546797889009881158/1565199822636716163).

## Navigation

Ctrl-B then c creates a tab; | and - split right/down; s opens the native
session picker; w opens a floating terminal; z zooms; r reloads Lua; 1-9
select tabs. Ctrl-B twice sends a literal Ctrl-B.

Ctrl-B then x closes the focused pane, falling back to the tab/window.
Rex's built-in confirmation is activity-based, not unconditional; idle shells
and commands that do not report activity may close without a prompt.

Ctrl-B then p / n selects the previous / next Rex tab. Bare Ctrl-P / Ctrl-N
also switch tabs; those global shortcuts take precedence over terminal
applications' bindings for those keys.

Use Cmd-Option-arrow to focus Rex panes, or Cmd-[ / Cmd-] to cycle through
them. These are native Rex shortcuts, with no process-detection plugin or
Neovim-to-Rex CLI handoff. Neovim's internal splits are navigated separately;
Ctrl-L clears native multicursors before moving to the right editor split.

No custom status widget or tmux vi copy mode is implemented. Use Rex's native
copy/paste shortcuts.

## Restart and Reboot

Since preview.23, Rex saves sessions, tabs, splits, floating panes, names and
IDs across server restarts. Terminals reopen as fresh shells in their saved
working directories; running programs and scrollback are not restored.
Closing the app without stopping its server leaves running programs intact.
No resurrect plugin is needed for basic layout restoration. See the
[preview.23 release notes](https://discord.com/channels/1546797889009881158/1547349572299395172/1565448157691777055).

Remote Control is needed for agent-driven client actions such as theme import,
and for new-assignment to select its new session, not ordinary keyboard
navigation. Keep it enabled when using new-assignment. Existing
Rex agent hooks and their trust remain managed separately.

## Assignments

Run new-assignment with its existing course, assignment and layout arguments.
Rex must already be open. The script requires one connected local Mac client,
or an explicit REX_CLIENT containing a full client ID or unique label from
`rex client ls`. It creates a named session with Neovim in the assignment
directory and explicitly selects that session in the app.

Existing directories and session labels are never overwritten. If launching
or selecting the session fails after generation, files are preserved and the
script prints recovery information. Do not blindly retry session creation.
