# Verification without uncontrolled resource use

Discover targets, dependent consumers, existing tests, and build configurations
from the affected code and repository documentation. Do not assume every ticket
uses simulation/debug. Preserve original regression coverage; add focused tests
with independent expectations. Use the configured caches, toolchains and Bazelisk
version from the ticket worktree. Never run `bazel clean` as a routine retry.

## Existing PR verification

Read approved lessons, then map the changed components to relevant CI suites using
the repository's current CI documentation, workflow conditions and comparable PRs
within the authorized read-only scope. Inspect the PR's labels and exact label
names required to enable those suites. Flag missing labels for relevant suites;
do not just report that the displayed checks are green.

Confirm that relevant suites ran for the current PR head. Distinguish skipped or
unrun suites from passing ones; default test jobs may omit manual integration
suites. Explain which label or trigger is needed to close a coverage gap. A
read-only verification request does not authorize editing labels or triggering
CI runs; report the needed action and preserve the requested access scope.

## Local builds and tests

Use the helper for all agent-managed Bazel build/test/query commands:

```sh
python3 <skill>/scripts/workflow.py bazel <KEY> -- cquery '<expression>'
python3 <skill>/scripts/workflow.py bazel <KEY> -- build <targets> <agreed-flags>
python3 <skill>/scripts/workflow.py bazel <KEY> -- test <targets> <agreed-flags>
```

The helper serializes these commands across ticket sessions and appends resource
limits: `--jobs=3`, `--local_resources=cpu=3`,
`--local_resources=memory=12288`, and for tests `--local_test_jobs=3`.
These are scheduling budgets, not OS memory caps. Do not bypass them by using
raw Bazel, another log root, a wrapper, or remote-resource overrides. Existing
manual user builds are not controlled by this lock; if competing builds or low
memory threaten responsiveness, defer and discuss it rather than kill user jobs.

The helper prints a private log path, writes exact command/result/fingerprint
evidence to `verification.md`, and detects candidate changes during execution.
Poll relevant log excerpts when a build runs for a while; give concise progress
updates without flooding the main context. Keep source unchanged during checks.
Interrupted and failed commands are not verification success. A passing command
with changed candidate inputs is invalidated and must be reassessed/repeated.
If the post-command snapshot cannot be read, the helper retains the command's
exit result and log but invalidates its verification evidence; reconcile the
missing inputs before resuming.

Use direct format/lint tools on changed files only. Inspect format changes;
avoid repository-wide rewrites or a `bazel run` target with unclear side effects.
Checks that require local generated outputs may alter ignored artifacts without
changing source; distinguish this from changed tracked/untracked candidate files.

Do not deploy, connect to live trading, alter shared services, use production
credentials, delete caches, or run uncontrolled external-service tests. Relevant
local builds/tests are authorized; new operational side effects are not. Identify
external/manual testing requirements and ask for direction. Never replace missing
runtime verification with a claim of full success.

At handoff distinguish passing, failing, blocked, and unrun checks, with exact
commands/configs, exit results and candidate fingerprints. Report existing or
unrelated failures separately without silently fixing them. Summarize logs and
reuse valid evidence instead of rerunning expensive unchanged verification.
