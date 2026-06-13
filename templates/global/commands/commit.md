---
description: "Generate a Conventional Commit message from staged changes"
allowed-tools: Bash(git:*)
---
Run: git diff --staged --stat && git diff --staged

Generate a Conventional Commits message:
  <type>(<scope>): <subject>

Types: feat|fix|refactor|perf|test|docs|chore|ci|build
Subject: imperative mood, ≤72 chars, no period.
Body: what + why (not how) — only if non-obvious.
Footer: breaking changes or "Closes #N"

Output ONLY the git commit command ready to copy-paste:
git commit -m "<message>"
