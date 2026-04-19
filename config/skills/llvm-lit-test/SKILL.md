---
name: llvm-lit-test
description: Run LLVM lit tests for the custom hardware targets
---

To lit test you must run the command
```zsh
sed -i '1c #!/usr/bin/env python3' build-x86_64/buildroot/build-llvm/bin/llvm-lit && build-x86_64/buildroot/build-llvm/bin/llvm-lit -v path/to/test
```
You must run this every time the project is rebuilt, so its safest to just do it every time. You may also need to provide --param ARCH_LABEL=<appropriate archlabel here (in upper case)>
