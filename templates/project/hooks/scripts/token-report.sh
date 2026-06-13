#!/usr/bin/env bash
# PostCompact — log compact event to MEMORY.md so you know when context was trimmed
MEMORY="${CLAUDE_PROJECT_DIR:-.}/.claude/MEMORY.md"
[[ ! -f "$MEMORY" ]] && exit 0
printf '\n## Compact @ %s\n- Context summarized. Run /user:context to see new %% full.\n- Resume tip: re-read key files before continuing deep work.\n' \
  "$(date '+%Y-%m-%d %H:%M')" >> "$MEMORY"
exit 0
