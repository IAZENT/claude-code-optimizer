---
name: team-status
description: Shows each role's current branch/worktree + open contracts.
tools: Read, Bash
model: claude-sonnet-4-6
---
Read .claude/team.config.json. Read .claude/INTERFACES.md.
Run `git branch -a` and `git worktree list`.
Report the current status of each role.
