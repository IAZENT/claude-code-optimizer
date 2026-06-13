---
name: lean
description: >
  Activate lean Chain-of-Draft mode for the current request. Auto-triggered when
  the user says "quick", "simple", "just", "fast", "routine", "lean", or the task
  is clearly a rename, lookup, boilerplate, or single-file edit. Saves 80-90%
  of reasoning tokens vs standard Chain-of-Thought.
---
LEAN MODE ACTIVATED for this request:
1. Reason in ≤5-word draft bullets — not full sentences
2. Skip self-evident steps entirely
3. Output only final answer/code — no preamble, no summary
4. Do not spawn subagents unless explicitly asked
5. Read only files you have been directly asked to read
6. If uncertain: state it in ≤1 sentence, then proceed with best guess

Prefix response with: [lean]
