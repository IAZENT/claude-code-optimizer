#!/usr/bin/env bash
# SessionStart — inject codebase map + session memory into new sessions

# Clear session-scoped state
rm -f "${CLAUDE_PROJECT_DIR}/.claude/.session/read-cache.jsonl" 2>/dev/null || true
rm -f "${CLAUDE_PROJECT_DIR}/.claude/.session/effort.txt" 2>/dev/null || true

CONTEXT="${CLAUDE_PROJECT_DIR}/.codesight/CONTEXT.md"
MEMORY="${CLAUDE_PROJECT_DIR}/.claude/MEMORY.md"
OUT=""
[[ -f "$CONTEXT" ]] && OUT+="## Codebase Map\n$(cat "$CONTEXT")\n\n"
[[ -f "$MEMORY"  ]] && OUT+="## Session Memory\n$(cat "$MEMORY")\n"
if [[ -n "$OUT" ]]; then
  ESCAPED=$(printf '%s' "$OUT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null \
    || printf '%s' "$OUT" | jq -Rs . 2>/dev/null \
    || printf '"%s"' "$(echo "$OUT" | sed 's/"/\\"/g')")
  printf '{"additionalContext": %s}\n' "$ESCAPED"
fi
exit 0
