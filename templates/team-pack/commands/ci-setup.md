---
name: ci-setup
description: Generates CI workflow based on detected stack and role paths.
tools: Write, Bash
model: claude-sonnet-4-6
---
Read .claude/team.config.json.
Generate a CI workflow (.github/workflows/ci.yml or .gitlab-ci.yml based on hosting).
Include lint, test, build per role's paths.
