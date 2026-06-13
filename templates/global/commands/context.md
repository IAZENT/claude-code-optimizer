---
description: "Debug context state — see what Claude has loaded"
allowed-tools: Read, Bash(cat:*)
---
Report context state:
1. Global CLAUDE.md loaded? (check ~/.claude/CLAUDE.md first 10 lines)
2. Project CLAUDE.md loaded? (check ./CLAUDE.md first 10 lines)
3. MEMORY.md exists? Show last 20 lines.
4. .codesight/CONTEXT.md exists? Show byte count.
5. Estimate context window % full from message count.

| Item                | Status         | Size   |
|---------------------|----------------|--------|
| Global CLAUDE.md    | loaded/missing | ?b     |
| Project CLAUDE.md   | loaded/missing | ?b     |
| MEMORY.md           | loaded/missing | ?b     |
| Codebase index      | loaded/missing | ?b     |
| Context window      | ~?% full       |        |
