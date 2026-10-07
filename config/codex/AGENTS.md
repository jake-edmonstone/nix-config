# Engine guidance

Before changing code in a Git checkout, compare its resolved Git common directory
(`git rev-parse --path-format=absolute --git-common-dir`) with that of
`/scratch/dev/engine`. If they match, read
`~/.local/share/engine-tickets/preferences.md` and
`~/.local/share/engine-tickets/lessons.md`. Apply approved preferences and relevant
lessons to engine code changes, including ordinary edits outside a ticket workflow.
If either file is missing, ask for guidance before editing engine code. Ignore this
section in other repositories, and do not scan the engine for unrelated tasks.

The full ticket workflow runs only when explicitly invoked as
`$engine-ticket-workflow`. Reading these preferences does not authorize delegation,
builds, a full ticket workflow, commits, pushes, PR changes, or deployment.
