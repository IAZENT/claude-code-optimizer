---
description: "Full feature workflow: Research → Plan → Implement → Validate"
argument-hint: "Feature description"
---
Phase 1 — RESEARCH (spawn researcher subagent):
Explore relevant code. Return: files to touch, patterns, risks.
Do NOT start implementing.

Phase 2 — PLAN (main context):
Numbered plan, max 10 steps.
STOP. Wait for approval before Phase 3.

Phase 3 — IMPLEMENT (after approval only):
Step by step. Show diff after each step. Confirm before proceeding.

Phase 4 — VALIDATE (spawn tester subagent):
Run full test suite. Return: pass/fail + root causes.

Feature: $ARGUMENTS
