---
description: "Compress context to MEMORY.md — do this before /compact"
allowed-tools: Read, Bash(git:*)
---
Context compression checkpoint:
1. Summarize what's been done this session (3-5 bullets max)
2. List open decisions or blockers (max 3)
3. List files modified and why (file → one-line reason)
4. Write to .claude/MEMORY.md under ## Session [YYYY-MM-DD HH:MM]
5. Output: "Context compressed. Safe to /compact now." then STOP.
