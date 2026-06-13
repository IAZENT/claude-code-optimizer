#!/usr/bin/env bash
# PreToolUse:Write|Edit — blocks hardcoded secrets in file writes
INPUT=$(cat)
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // .tool_input.new_string // ""' 2>/dev/null || true)
PATTERNS='(sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36,}|AKIA[A-Z0-9]{16}|AIza[0-9A-Za-z_-]{35}|OPENAI_API_KEY=[^< ]{8,}|Bearer [A-Za-z0-9._-]{20,})'
if echo "$CONTENT" | grep -qE "$PATTERNS" 2>/dev/null; then
  printf '{"decision":"block","reason":"Hardcoded secret detected. Use env vars: process.env.KEY or os.environ[\"KEY\"]. Placeholder format: <YOUR_API_KEY>."}\n'
  exit 2
fi
exit 0
