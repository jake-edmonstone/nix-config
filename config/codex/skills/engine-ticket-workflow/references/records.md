# Private records and approvals

The helper defaults to `~/.local/share/engine-tickets/`. It creates owner-accessible
Markdown records without overwriting existing guidance. Company content belongs
here, never in the workflow's Nix-managed files. Preserve sources until the user
requests removal. Record any copied attachment locally with provenance and use
only relevant excerpts in agent packets. Do not fetch linked systems without an
explicit read-only request; request missing source content when access fails.

## Guidance

- `preferences.md` contains the user's approved working preferences.
- `lessons.md` contains approved, scoped lessons with sources and concrete checks.
- `pending-lessons.md` holds proposed lessons until the user approves them.

There is no required entry schema: descriptive headings and plain prose suffice.
Direct user edits to approved files are approved guidance. Ask about conflicts or
unclear scope. Agent-inferred feedback must retain the original source and remain
pending; the agent must not approve its own proposals. Deduplicate relevant lessons
rather than growing a transcript of all tickets.

## Ticket dossier

`tickets/<KEY>/` contains:

- `context.md`: original ticket text, supplied conversations/files, recollections,
  source links and dates, and distinctions between facts and assumptions.
- `brief.md`: agreed behavior, acceptance criteria, non-goals, and open questions.
- `plan.md`: minimal implementation, existing patterns/helpers with source locations,
  changed-file justifications, retained tests, and verification commands/configs.
- `status.md`: worktree/branch, fixed comparison-base commit, starting HEAD, stage,
  approvals, candidate fingerprints, outstanding work and decisions.
- `baseline.patch`: original tracked changes, plus baseline untracked paths in
  `status.md`. Inspect these before editing; never discard user changes.
- `verification.md`: command evidence written by the build helper and any other
  exact checks, with results, candidate fingerprints, and limitations.
- `reviews/`: the main agent saves separate initial reviewer reports by stage,
  role, and round, plus finding dispositions and supporting evidence.
- `pr-draft.md`: the final proposed title/body, full Jira link, change summary,
  verification and known limits, consistent with the engine PR guidelines.

Record the user's explicit brief, plan and final approvals with date and scope.
Absence of a reply or a passing review is not approval. These are conversational
gates, independent of the CLI's shell approval policy. Until a gate is approved,
do not proceed to the next stage. Private record updates and read-only exploration
are permitted while preparing a gate; engine implementation is not.

Use `python3 <skill>/scripts/workflow.py snapshot <KEY>` before/after review and
verification, and record its output with the evidence. It covers HEAD, branch,
tracked changes, untracked file content, approved guidance, context, brief, and plan.
Compare current fingerprints to evidence on resume. Changed code invalidates
affected review/tests; changed guidance or requirements requires assessing and
repeating affected review. Material requirements/design changes need renewed
approval. Do not automatically re-run every unchanged check.

If the ticket key is reused in a different worktree/branch, stop and reconcile
with the user. Do not silently reset the fixed base, overwrite approvals, or
combine two simultaneous implementations. Inspection of records is not proof
that the current worktree matches them; check Git state each time.
