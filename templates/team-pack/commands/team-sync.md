---
name: team-sync
description: Pulls latest INTERFACES.md and flags breaking changes.
tools: Bash, Read
model: claude-sonnet-4-6
---
Run `git fetch origin` and `git diff main...HEAD -- .claude/INTERFACES.md`.
Flag any breaking changes to the user.
