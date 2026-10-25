# Configuration Checks

Run from the repository root. The Lua tests use the Neovim plugins already
installed under its data directory; they do not install or update plugins.

```sh
PYTHONDONTWRITEBYTECODE=1 python -m unittest discover -s tests -p 'test_*.py' -v
NVIM_LOG_FILE=/tmp/nvim-upstream-test.log nvim --clean --headless -i NONE -n -l tests/test_nvim_upstream.lua "$PWD"
NVIM_LOG_FILE=/tmp/nvim-mini-files-test.log nvim --clean --headless -i NONE -n -l tests/test_mini_files_git.lua "$PWD"
for trigger in ctrl-l ctrl-h command; do
  env -u TMUX NVIM_NAV_LOAD="$trigger" NVIM_LOG_FILE=/tmp/nvim-navigator-test.log \
    nvim --headless -i NONE -n '+luafile tests/test_nvim_navigator.lua'
done
```

The Python tests check Fish's limit handling, the empty-course safety guard,
and tmux navigation detection/configuration parsing. The tmux test starts its
own server on a temporary socket, never the normal server. Temporary fixture
directories are moved to Trash using `trash`.

The process detector intentionally scans the whole tty, as upstream does:
stopped/zombie editors are ignored, but running background editors also match.

The mini.files test checks rendered status placement/colors, directory
aggregation, asynchronous/cache behavior, symlinks, and an actual rename.
The other Lua test covers native clipboard/spelling, snippet jumps and fallback,
multicursor-aware Ctrl-L, terminal-mode mappings, and unlimited sticky context.
The navigator integration test loads the real LazyVim config and executes native
`Q` and remapped Ctrl-L/Ctrl-H keypresses. Each invocation checks a different
first-load path, including Ctrl-L itself. Unsetting `TMUX` keeps its navigation
inside the test editor instead of sending commands to an existing tmux server.

## tmux Version Trial

To exercise a different tmux build without changing the normal server, prepend
its `bin` directory to `PATH` when running the Python checks. Before retiring a
rendering workaround, also test the session popup interactively while Codex
streams output: automated configuration checks cannot confirm visual fidelity
in Ghostty.
