# Skills (~/.claude/skills/)

Each subdirectory is one skill: <name>/SKILL.md with YAML frontmatter
(name, description, optional allowed-tools/model) followed by instructions.

Unlike slash commands (.claude/commands/*.md, invoked as /user:name),
skills are loaded automatically when their `description` matches the
task — no explicit invocation needed. A command and a skill can coexist
for the same workflow; skills are the 2026-recommended shape going
forward because they support bundled scripts/reference files.

Project-local skills go in .claude/skills/ inside a repo and take
precedence over these global ones.

## Installed here
- commit-pr            — Conventional Commit + PR description from staged diff
- codebase-explainer   — architecture overview, delegates exploration to a subagent
- frontend-aesthetics  — fights the generic "AI slop" UI default; defers to
                          ./DESIGN.md when present (see /project:design)
- lean                 — auto-activates Chain-of-Draft + low-effort for simple tasks
