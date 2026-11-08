# Configuration Checks

Run from the repository root. The Lua tests use the Neovim plugins already
installed under its data directory; they do not install or update plugins.

```sh
PYTHONDONTWRITEBYTECODE=1 python -m unittest discover -s tests -p 'test_*.py' -v
NVIM_LOG_FILE=/tmp/nvim-upstream-test.log nvim --clean --headless -i NONE -n -l tests/test_nvim_upstream.lua "$PWD"
NVIM_LOG_FILE=/tmp/nvim-mini-files-test.log nvim --clean --headless -i NONE -n -l tests/test_mini_files_git.lua "$PWD"
NVIM_LOG_FILE=/tmp/nvim-navigation-test.log nvim --headless -i NONE -n '+luafile tests/test_nvim_windows.lua'
```

The Python tests check Fish's limit handling, the empty-course safety guard,
and assignment generation/Rex launching with a stub CLI. They never edit real
coursework or create live Rex sessions. Temporary fixtures go to Trash.

The mini.files test checks rendered status placement/colors, directory
aggregation, asynchronous/cache behavior, symlinks, and an actual rename.
The other Lua test covers native clipboard/spelling, snippet jumps and fallback,
multicursor-aware Ctrl-L and unlimited sticky context. The window integration
test loads real LazyVim and executes native Q and Ctrl-L/Ctrl-H keypresses,
without any multiplexer navigation plugin.
