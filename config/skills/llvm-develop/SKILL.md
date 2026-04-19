---
name: llvm-develop
description: Orchestrate a full development workflow — research, plan, test, code, review — for LLVM changes
argument-hint: <task description or Jira URL>
---

# LLVM Development Workflow

Execute a full development cycle for the following task:

$ARGUMENTS

## Workflow

First, determine whether this task is a **feature/fix** (adds or changes behavior) or a **refactor** (changes internals without changing behavior). This affects which phases run.

### Phase 1: Research
Delegate to the llvm-researcher agent to analyze the codebase and gather context about the task. The researcher should identify existing patterns, relevant files, and how other LLVM targets handle similar features.

Wait for the research report before proceeding.

### Phase 2: Plan
Delegate to the llvm-planner agent to create a concrete implementation plan based on the research. The plan should break the work into ordered steps with specific files and patterns to follow.

Wait for user approval of the plan before proceeding.

### Phase 3: Tests
**Skip this phase for refactors** — existing tests serve as the verification that behavior is preserved.

For features/fixes: delegate to the llvm-test-writer agent to write failing lit tests that define the expected behavior based on the plan. Tests should fail with the current code.

### Phase 4: Implement
Delegate to the llvm-coder agent to implement the changes following the plan. Build and run tests after each step.

For refactors: run existing tests early and often to catch regressions. All existing tests must keep passing.

### Phase 5: Review
Delegate to the llvm-reviewer agent to do a skeptical review of all changes. If the reviewer has MUST FIX items, send them back to the llvm-coder agent and repeat phases 4-5 until the reviewer approves.

For refactors: the reviewer should pay extra attention to behavioral equivalence — no subtle semantic changes hiding behind "cleanup."

### Phase 6: Summary
After approval, provide a final summary:
- What was changed and why
- Files modified
- Test results
- Any follow-up work needed
