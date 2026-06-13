#!/usr/bin/env bash
# PreCompact — auto-trim MEMORY.md when > 100 lines to prevent stale context bloat
MEMORY="${CLAUDE_PROJECT_DIR:-.}/.claude/MEMORY.md"
[[ ! -f "$MEMORY" ]] && exit 0
LINES=$(wc -l < "$MEMORY" | tr -d ' ')
if [[ $LINES -gt 100 ]]; then
  HEADER=$(head -8 "$MEMORY")
  TAIL=$(tail -60 "$MEMORY")
  {
    echo "$HEADER"
    echo ""
    echo "---"
    printf "<!-- Auto-trimmed at %s: %d→68 lines -->\n" "$(date '+%Y-%m-%d %H:%M')" "$LINES"
    echo ""
    echo "$TAIL"
  } > "$MEMORY"
fi
printf '{"additionalContext":"## Context compacted at %s\nSee .claude/MEMORY.md for session history.\n"}\n' "$(date '+%Y-%m-%d %H:%M')"
exit 0
