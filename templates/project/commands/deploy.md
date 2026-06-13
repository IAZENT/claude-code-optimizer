---
description: "Pre-deploy checklist — run before any deployment"
allowed-tools: Bash(git:*), Bash(pnpm:*)
---
Pre-deploy checklist — report [PASS] or [FAIL] for each:

1. All tests pass: pnpm test
2. No TypeScript errors: pnpm tsc --noEmit
3. No lint errors: pnpm lint
4. No uncommitted changes: git status
5. On correct branch: git branch --show-current
6. .env.example up to date vs .env (check for missing keys)
7. No TODO(debt) in this diff: git diff main..HEAD | grep -c "TODO(debt)"
8. No hardcoded secrets: git diff main..HEAD | grep -E "(sk-|ghp_|AKIA)"

Block deployment if ANY FAIL.
