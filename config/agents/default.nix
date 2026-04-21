# Cross-platform agent definitions. Each body is a plain markdown file in
# this directory (no YAML frontmatter, no TOML wrapping). modules/claude.nix
# and modules/codex.nix each wrap these into their respective on-disk format
# (Claude: .md with YAML frontmatter; Codex: .toml with developer_instructions).
#
# Generator defaults live in the consuming modules:
#   - claude.model = "opus"
#   - claude.skills = []
#   - codex.model_reasoning_effort = "high"
#
# To add an agent:
#   1. Drop <name>.md (body only, no frontmatter) in this directory.
#   2. Add an entry below with claude.tools (required) and any overrides.
{
  context-builder = {
    description = "Reads and internalizes a branch's changes from a base commit to HEAD. Use at session start to front-load context.";
    body = ./context-builder.md;
    claude.tools = "Read, Grep, Glob, Bash";
  };

  llvm-coder = {
    description = "Implements features and fixes in the LLVM codebase. Use after tests are written to make them pass.";
    body = ./llvm-coder.md;
    claude.tools = "Read, Write, Edit, Bash, Glob, Grep";
    claude.skills = [
      "llvm-lit-test"
      "llvm-build"
    ];
  };

  llvm-planner = {
    description = "Turns an LLVM research report into a concrete, ordered implementation plan. Use after research, before test writing and coding.";
    body = ./llvm-planner.md;
    claude.tools = "Read, Grep, Glob";
  };

  llvm-researcher = {
    description = "Researches the LLVM codebase to understand existing patterns, conventions, and architecture before implementation begins. Use before coding to gather context.";
    body = ./llvm-researcher.md;
    claude.tools = "Read, Grep, Glob, Bash, WebSearch, WebFetch";
    claude.skills = [ "llvm-build" ];
  };

  llvm-reviewer = {
    description = "Skeptically reviews LLVM code changes for correctness, style, and completeness. Use after the coder finishes implementation.";
    body = ./llvm-reviewer.md;
    claude.tools = "Read, Grep, Glob, Bash";
    claude.skills = [
      "llvm-lit-test"
      "llvm-build"
    ];
  };

  llvm-test-writer = {
    description = "Writes or updates LLVM lit tests that define expected behavior before implementation. Use after research, before coding.";
    body = ./llvm-test-writer.md;
    claude.tools = "Read, Write, Edit, Glob, Grep, Bash";
    claude.skills = [
      "llvm-lit-test"
      "llvm-build"
    ];
  };

  nvim-lua-perf = {
    description = "Analyzes Neovim Lua configuration files for performance issues, deprecated APIs, and modern best practices.";
    body = ./nvim-lua-perf.md;
    claude.tools = "Read, Grep, Glob, WebSearch, WebFetch";
  };

  typst-proofreader = {
    description = "Proofreads Typst documents for spelling, grammar, and terminology inconsistencies.";
    body = ./typst-proofreader.md;
    claude.tools = "Read, Grep, Glob";
  };

  typst-reviewer = {
    description = "Reviews Typst code for deprecated APIs, performance issues, idiomatic patterns, and cleaner structure.";
    body = ./typst-reviewer.md;
    claude.tools = "Read, Grep, Glob, WebSearch, WebFetch";
  };

  website-review = {
    description = "Reviews a website repository for style inconsistencies, performance issues, and best practices. Accepts a path to a website repo.";
    body = ./website-review.md;
    claude.tools = "Read, Grep, Glob, Bash, WebFetch";
  };
}
