---
description: "Show today's token spend, context health, and recommendations. Run when you want to know if you should compress or start a fresh session."
allowed-tools: Bash(cat:*), Bash(find:*), Bash(wc:*), Bash(python3:*)
---
Report token budget status:

1. Check budget config: cat ~/.claude/budget.conf (show daily limit or note "not set, default 200k")
2. Estimate today's usage from session logs:
   find ~/.claude/projects -name "*.jsonl" | head -3 (verify log location exists)
3. If ccusage is installed: run `ccusage today` and show output
4. Show current context: run /context
5. Give a clear recommendation: compress / continue / start fresh

Format:
| Metric           | Value        |
|------------------|--------------|
| Daily limit      | ? tokens     |
| Est. used today  | ? tokens     |
| % of budget      | ?%           |
| Context window   | ~?% full     |
| Recommendation   | ...          |

Rules:
- If budget < 20% remaining: strongly recommend /user:compress → /compact → fresh session
- If context > 60% full: recommend /user:compress now
- If both OK: "On track — continue"
