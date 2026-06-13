#!/usr/bin/env bash
# effort-gate-pre.sh — Gate heavy commands on low effort mode
# Trigger: PreToolUse:Bash

set -euo pipefail

EFFORT_FILE=".claude/.session/effort.txt"
if [[ -f "$EFFORT_FILE" ]]; then
  EFFORT=$(cat "$EFFORT_FILE")
  if [[ "$EFFORT" == "low" ]]; then
    INPUT=$(cat)
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
    
    # Heavy patterns: full test suites, rebuilds
    if echo "$COMMAND" | grep -Eq '^(npm test|pytest|docker build)$'; then
      cat <<EOF
{
  "decision": "block",
  "reason": "Low-effort mode: scope this command to the relevant file/module, or run /user:effort-high if you genuinely need the full run."
}
EOF
      exit 2
    fi
  fi
fi

cat <<EOF
{
  "decision": "allow"
}
EOF
