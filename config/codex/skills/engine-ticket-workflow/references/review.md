# Independent adversarial review

Run two fresh reviewers for design and again for the frozen candidate code:

- `engine_correctness_reviewer`: requirements, behavior, edge cases, interfaces,
  compatibility, state/lifetime/concurrency risks, and test coverage.
- `engine_patterns_reviewer`: concrete surrounding patterns and existing helpers,
  minimal diff, redundant work, new abstractions, and approved user preferences.

Delegate explicitly with these roles. If spawning tools expose history controls,
use no inherited conversation (`fork_turns="none"` or `fork_context=false`, as
supported). Otherwise use a fresh session with a task packet; never claim reviewer
independence when full implementation history was inherited. Limit each reviewer
to its assigned stage and affected paths. Reviewers must not edit files, run
builds/tests, spawn more agents, or use externally mutating tools.

If native named-agent selection is unavailable, read the corresponding
`~/.codex/agents/<name>.toml` and supply its developer instructions to a fresh
subagent/session with its explicit model, effort and Standard service tier.
Inspect effective settings where exposed; distinguish configured metadata from
per-turn execution telemetry. Do not claim native role discovery from merely
reading the TOML. Never silently inherit a higher-cost setting. If selection
cannot be established or the model is unavailable, stop and ask; do not retry
with another model automatically.

## Initial packet

Include the stage/round, approved brief, private guidance paths, this procedure,
worktree and fixed base, relevant source locations, and scope of the assignment.
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
