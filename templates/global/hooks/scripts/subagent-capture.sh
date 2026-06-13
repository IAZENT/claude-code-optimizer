#!/usr/bin/env bash
# SubagentStop — write subagent findings to MEMORY.md so they survive context close
INPUT=$(cat)
AGENT=$(echo "$INPUT"  | jq -r '.agent_name // "subagent"' 2>/dev/null || echo "subagent")
OUTPUT=$(echo "$INPUT" | jq -r '.output // ""'              2>/dev/null || true)
MEMORY="${CLAUDE_PROJECT_DIR:-.}/.claude/MEMORY.md"
[[ -n "$OUTPUT" && -f "$MEMORY" ]] && printf '\n## Subagent [%s] — %s\n%s\n' "$AGENT" "$(date '+%Y-%m-%d %H:%M')" "$OUTPUT" >> "$MEMORY"
exit 0
