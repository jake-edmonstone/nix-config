#!/usr/bin/env bash
# Claude Code status line — mirrors Powerlevel10k p10k.zsh style
# Colors: dir=#bd93f9 (purple), git=#ff79c6 (pink), user=#8be9fd (cyan)

input=$(cat)

cwd=$(jq -r '.workspace.current_dir // .cwd // ""' <<<"$input")
model=$(jq -r '.model.display_name // ""' <<<"$input")
used_pct=$(jq -r '.context_window.used_percentage // empty' <<<"$input")

# Shorten $HOME to ~
home="$HOME"
dir="${cwd/#$home/~}"

# Git branch (skip optional lock files)
git_branch=""
if [ -n "$cwd" ] && git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  git_branch=$(git -C "$cwd" -c core.fsmonitor=false symbolic-ref --short HEAD 2>/dev/null \
    || git -C "$cwd" -c core.fsmonitor=false rev-parse --short HEAD 2>/dev/null)
fi

# Build output
# dir: bold purple
printf '\033[1;38;2;189;147;249m%s\033[0m' "$dir"

# git: " on <branch>" in pink
if [ -n "$git_branch" ]; then
  printf ' \033[0;2mon \033[0m\033[38;2;255;121;198m%s\033[0m' "$git_branch"
fi

# model: dim, after a separator
if [ -n "$model" ]; then
  printf '  \033[2m%s\033[0m' "$model"
fi

# context window usage
if [ -n "$used_pct" ]; then
  used_int=$(printf '%.0f' "$used_pct")
  printf ' \033[2m[ctx: %s%%]\033[0m' "$used_int"
fi

printf '\n'
