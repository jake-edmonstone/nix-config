---
name: llvm-build
description: Build the LLVM project using the monolith build system
---

Build llvm-project with the following command. **Always run in background** — builds take a long time:
```zsh
MONOLITH_INSTALLROOT="$HOME/ws/monolith-install" INSTALLROOT="$(pwd)/build-install" /cb/tools/cerebras/cbrun/v0.3.2/cbrun -- srun -c32 make -j32 build
```

**Do not pipe build output into `tail`, `head`, or similar** — it can swallow errors and hang. Use `run_in_background` and read the output file when the build completes.
