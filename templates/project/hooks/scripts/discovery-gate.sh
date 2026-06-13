#!/usr/bin/env bash
# PreToolUse:Read|Grep — enforce codebase indexing before raw file reads
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || true)
if [[ "$FILE" =~ \.(ts|tsx|js|jsx|py|go|rs|java|rb|php|cs|swift|kt)$ ]]; then
  if [[ ! -f "${CLAUDE_PROJECT_DIR}/.codesight/CONTEXT.md" ]]; then
    printf '{"decision":"block","reason":"Codebase index not found. Run once from project root:\n  npx codesight --profile claude-code\n\nThis creates .codesight/CONTEXT.md and reduces token use 9-13x.\nTakes ~30 seconds. Then retry your request."}\n'
    exit 2
  fi
fi
exit 0
