---
description: "Security + perf + quality audit via reviewer subagent"
allowed-tools: Read, Grep, Bash(git:*)
---
Run: git diff HEAD
Spawn the reviewer subagent on the full diff.
Return findings: CRITICAL → HIGH → MED → LOW
No praise. Direct and specific.
