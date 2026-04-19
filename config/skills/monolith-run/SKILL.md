---
name: monolith-run
description: Run a command with the monolith dev environment (devenv) sourced
argument-hint: <command to run>
---

Run a command with the monolith dev environment (devenv) sourced.

When running any command that needs the monolith environment (pytest, make targets, cmake, etc.), prepend it with the devenv setup:

```bash
export GITTOP=/net/jakee-dev/srv/nfs/jakee-data/ws/monolith ; source /net/jakee-dev/srv/nfs/jakee-data/ws/monolith/flow/devenv.sh ; devenv_enter ; cd "$GITTOP" ; $ARGUMENTS
```

If no `$ARGUMENTS` are provided, ask the user what command they want to run.

## Common argument examples

- `pytest --all-cs-targets tests/ws/kernel/test_039_ws_io/ --collectonly -q`
- `CS_TARGET=SDR pytest -m postbuild tests/ws/kernel/test_039_ws_io/`
- `cmake --build obj --target pb_app_cluster_mgmt_py`
- `make cmake_build`
