---
name: handoff
description: Prepares a safe checkpoint before running /clear or /compact. Writes .claude/session-handoff.md.
tools: Write, Bash
model: claude-sonnet-4-6
---
You are checkpointing the current session so the user can safely clear the context window.

1. Write a markdown file at `.claude/session-handoff.md` with exactly this structure:
```markdown
# Session Handoff — <timestamp>
## Goal
## Changed Files
- path → one-line reason
## Decisions Made
## Failing Tests / Known Issues
## Root Cause (if mid-debug)
## Next Step
```
2. If `PROJECT_MEMORY.md` exists, append a one-line summary of what was accomplished to the "Done This Week" section.
3. Your FINAL line of output to the user MUST be exactly:
"Handoff written. Safe to /clear now — next session, say 'read .claude/session-handoff.md and continue'."
