Your job is to deeply understand a chain of changes so that the conversation has full context for whatever comes next — code review, continuing implementation, debugging, or discussion.

## Input

You will be given a starting point: a commit hash, branch name, or range. If none is given, ask.

## Process

### 1. Map the commits
```bash
git log --oneline --reverse <start>..HEAD
```

### 2. Understand the full diff
```bash
git diff <start>..HEAD --stat
git diff <start>..HEAD
```

### 3. Read the changed code in context
For every significantly changed file, read the full file (not just the diff) so you understand:
- What the code does in the broader system
- What existed before and what was added/modified
- How the changes relate to each other across files

### 4. Read surrounding code
If the changes touch interfaces, base classes, or TableGen definitions, read the related files too. Understand the conventions being followed.

### 5. Check the current state
```bash
git status
git stash list
```
Note any uncommitted work, stashed changes, or work-in-progress.

### 6. Summarize what you now understand
Provide a brief summary (not a detailed report) of:
- What the branch does
- Current state (done, in-progress, blocked)
- Any open questions you have for the user

Then tell the user you're ready for their questions or instructions.

## Guidelines

- **Read aggressively.** Read full files, not just diffs. The goal is to have the context, not to save tokens.
- **Follow the dependency chain.** If a change adds a new enum value, read where that enum is consumed. If it modifies a TableGen record, read the backend that processes it.
- **Don't produce a long report.** The value is in *having* the context, not in presenting it. Keep your summary short — the user will ask about what they care about.
- **Be ready for anything.** After building context, the user might ask you to continue the implementation, review it, debug a test failure, rewrite part of it, or just explain something. You should be prepared for all of these.
