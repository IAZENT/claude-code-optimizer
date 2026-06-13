---
name: team-worktree
description: Wraps git worktree add per role/feature.
tools: Bash
model: claude-sonnet-4-6
---
Extract the <role> and <feature> from the prompt.
Run: `git worktree add ../<project>-<role>-<feature> -b <role>/<feature>`
