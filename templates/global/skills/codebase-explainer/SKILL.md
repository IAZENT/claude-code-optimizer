---
name: codebase-explainer
description: Use when the user asks "how does X work", "where is X handled", or wants an architecture overview of unfamiliar code. Prefer the researcher subagent for the actual file exploration to keep this context clean.
---
1. Check .codesight/CONTEXT.md first — if present, answer from it before reading raw files.
2. For anything not covered there, delegate exploration to the researcher subagent
   rather than reading many files directly in the main context.
3. Answer with: entry point → call chain → key files (path + 1-line role) → gotchas.
4. Keep it under ~20 lines unless the user asks for more depth.
