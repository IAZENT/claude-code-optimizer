#!/usr/bin/env bash
# PostToolUse — warn when daily token budget hits 80% (uses local JSONL logs)
BUDGET_FILE="$HOME/.claude/budget.conf"
BUDGET=${CLAUDE_DAILY_BUDGET:-$(cat "$BUDGET_FILE" 2>/dev/null | grep -o '[0-9]*' | head -1 || echo "")}
BUDGET=${BUDGET:-200000}
LOG_DIR="$HOME/.claude/projects"
USED=0
if [[ -d "$LOG_DIR" ]]; then
  TODAY=$(date +%Y-%m-%d)
  USED=$(find "$LOG_DIR" -name "*.jsonl" -newer /tmp/.ccg_ref_$(date +%Y%m%d) 2>/dev/null \
    | xargs grep -h '"usage"' 2>/dev/null \
    | python3 -c "
import sys, json
t = 0
for line in sys.stdin:
    try:
        d = json.loads(line)
        u = d.get('usage', {})
        if isinstance(u, dict):
            t += u.get('input_tokens', 0) + u.get('output_tokens', 0)
    except: pass
print(t)
" 2>/dev/null || echo 0)
fi
touch /tmp/.ccg_ref_$(date +%Y%m%d) 2>/dev/null || true
PCT=$(( USED * 100 / BUDGET )) 2>/dev/null || PCT=0
if [[ $PCT -ge 80 ]]; then
  printf '{"decision":"warn","reason":"⚠️  Token budget %d%% used (~%d/%d tokens today). Run /user:compress → /compact, or start a fresh session. Use /user:budget-check for details."}\n' "$PCT" "$USED" "$BUDGET"
fi
exit 0
