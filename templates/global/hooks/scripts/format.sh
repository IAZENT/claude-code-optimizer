#!/usr/bin/env bash
# PostToolUse:Write|Edit — auto-formats the file Claude just wrote
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null || true)
[[ -z "$FILE" || ! -f "$FILE" ]] && exit 0
case "$FILE" in
  *.ts|*.tsx|*.js|*.jsx|*.json|*.css|*.md) npx --yes prettier --write "$FILE" 2>/dev/null || true ;;
  *.py) python -m black "$FILE" 2>/dev/null || python3 -m black "$FILE" 2>/dev/null || true ;;
  *.go) gofmt -w "$FILE" 2>/dev/null || true ;;
  *.rs) rustfmt "$FILE" 2>/dev/null || true ;;
esac
exit 0
