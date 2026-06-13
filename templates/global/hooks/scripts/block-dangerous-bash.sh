#!/usr/bin/env bash
# PreToolUse:Bash — blocks destructive commands
INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || true)
DANGEROUS='(rm -rf /|sudo rm -rf|DROP TABLE|DROP DATABASE|chmod 777|dd if=|mkfs\.|fdisk)'
if echo "$CMD" | grep -qE "$DANGEROUS" 2>/dev/null; then
  printf '{"decision":"block","reason":"Dangerous command blocked. If intentional, run manually: %s"}\n' "$CMD"
  exit 2
fi
exit 0
