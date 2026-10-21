# Independent adversarial review

Run two fresh reviewers for design and again for the frozen candidate code:

- `engine_correctness_reviewer`: requirements, behavior, edge cases, interfaces,
  compatibility, state/lifetime/concurrency risks, and test coverage.
- `engine_patterns_reviewer`: concrete surrounding patterns and existing helpers,
  minimal diff, redundant work, new abstractions, and approved user preferences.

Use these roles through the launcher below, each in a fresh CLI session with a
separate task packet and no inherited implementation conversation. Limit each reviewer
to its assigned stage and affected paths. Reviewers must not edit files, run
builds/tests, spawn more agents, or use externally mutating tools.

## Reviewer launcher

Prepare each packet as an owner-only file inside the ticket's private `reviews/`
directory, following the packet guidance below. From the existing worktree run:

```sh
python3 <this-skill>/scripts/workflow.py review <KEY> \
  --role engine_correctness_reviewer --stage design --round 1 \
  --packet ~/.local/share/engine-tickets/tickets/<KEY>/reviews/design-correctness-packet-1.md
```

Run the same command with `engine_patterns_reviewer` and its own packet. Use
`--stage code` for candidate review and the applicable round number for re-review.
At most two reviewer processes may run concurrently; keep the candidate frozen.
Do not use native spawning tools first or ask to use Priority when they fail.

The helper reads `~/.codex/agents/<name>.toml` and launches a fresh, ephemeral
`codex exec` with its explicit model, effort, developer instructions, Standard
(`service_tier="default"`), read-only sandbox, and no approvals. It uses `codex-vdi`
when installed (otherwise `codex --no-daemon`), preserving the normal connection
route. It disables nested delegation, app tools, and web search: provide the
relevant retrieved context in the packet instead of making reviewers depend on
Jira availability. These overrides affect only the reviewer, not the main session.

The helper saves private logs/settings under `reviews/`, accepts a completed
report only if the candidate fingerprint and packet are unchanged, and refuses
to overwrite an existing report or run the same role/round concurrently. Configured settings
are not per-turn execution telemetry; inspect any exposed telemetry separately.
For a genuine CLI/auth/model failure, inspect the saved logs and stop; do not
automatically retry, change models, raise effort, relax permissions, or use Priority.
The default timeout is ten minutes; `--timeout <seconds>` changes only that deadline.

## Initial packet

Include the stage/round, approved brief, private guidance paths, this procedure,
worktree and fixed base, repository style-guide path, relevant source locations,
and scope of the assignment.
For design, include the proposed plan and reuse locations. For code, provide the
candidate fingerprint and neutral verification commands/results. Permit independent
read-only source exploration. Exclude progress notes, the implementer's defense,
previous review dispositions, and the other reviewer's initial report. Explicitly
tell reviewers which files they should not read. This is an instruction boundary,
not enforced isolation; do not promise mechanically blinded review.

Ask each reviewer to return:

- Findings with severity, precise location/plan step, a concrete scenario or
  approved-rule violation, evidence, and required correction or smaller alternative.
- Questions and unverified risks separately from confirmed defects.
- Applicable preference/lesson checks and any verification gaps.
- No actionable findings if none are supported; never a minimum finding count.

Both correctness and minimal-diff review matter. Passing tests do not settle
misinterpreted requirements. Minimal diff does not justify missing tests, dense
code, or ignoring original coverage. Preserve necessary inheritance even when
the user generally prefers `final`; do not demand unrelated style normalization.
Apply the `final` preference only to newly introduced leaf classes and structs.
Adding `final` to an existing type, even one changed for the ticket, is unwanted
diff churn.

Check newly introduced variable declarations, including structured/loop bindings,
and newly introduced member functions for const-correctness. Require const where
their intended use permits it, and justify mutable exceptions from actual writes,
called interfaces, move behavior or assignability. Nearby non-const code is not
a reason to omit const from new declarations. Do not demand const additions to
pre-existing variables or methods, even in otherwise changed code.
For new variable declarations, prefer constexpr over const when the existing
initialization permits it and semantics are preserved. Do not request additional
declarations, literal extraction or restructuring solely to use constexpr, or
constexpr upgrades to pre-existing declarations.

The patterns reviewer must read the repository's written style guide and check
new or materially changed code against it independently of formatter results and
nearby code. For C++ conditionals and loops, inspect both the full condition and
controlled body against the brace rules: a single-statement body alone does not
justify omitting braces. Check initialization forms, including explicit temporary
construction, against the guide's recommendations. Prefer brace initialization
where recommended and semantics are preserved; check initializer-list overload
selection and narrowing before changing delimiters. Check other applicable rules
that the formatter may not enforce, distinguishing recommendations from hard
requirements. Cite the rule and source for findings; do not expand this check
into cleanup of untouched code.

## Resolution and re-review

Save initial reports separately in `reviews/<stage>-<role>-<round>.md`. The main
agent then assesses each finding using code, requirements, or a reproduction.
Record it as confirmed/fixed, disputed with evidence, or needing user direction.
Do not accept a finding merely because a reviewer is confident, or dismiss one
merely because the implementation agent disagrees.

Have the main agent run any necessary bounded verification through the shared
build helper. Fix confirmed issues, then rerun affected checks and re-review
changed areas plus their relevant callers. For a focused re-review, provide the
specific finding and fix without repeating the entire ticket history. Broaden
review when the fix changes wider behavior.

Count unsuccessful fix/review rounds separately for design and code in `status.md`.
After three unsuccessful rounds, or an unresolved design dispute, stop and ask
the user. Do not declare complete with an unresolved actionable finding; report
unverified risks and external verification gaps explicitly. Reviewer agreement
is not a guarantee of correctness.
