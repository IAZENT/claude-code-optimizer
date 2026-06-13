---
name: commit-pr
description: Use when the user wants to commit staged changes or open/describe a pull request. Generates a Conventional Commit message and a PR title/description from the staged diff.
allowed-tools: Bash(git:*)
---
1. Run: git diff --staged --stat && git diff --staged
2. If nothing is staged, say so and stop.
3. Generate a Conventional Commits message:
   <type>(<scope>): <subject>
   Types: feat|fix|refactor|perf|test|docs|chore|ci|build
   Subject: imperative mood, ≤72 chars, no period.
   Body: what + why (not how) — only if non-obvious.
4. If the user asked for a PR, also output:
   - PR title (same as commit subject)
   - PR description: ## Summary (2-3 bullets) + ## Test plan
5. Output the ready-to-run command:
   git commit -m "<message>"
