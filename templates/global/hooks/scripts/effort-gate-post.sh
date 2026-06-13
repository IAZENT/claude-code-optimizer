#!/usr/bin/env bash
# effort-gate-post.sh — Tighter truncation on low effort mode
# Trigger: PostToolUse:Bash

set -euo pipefail

EFFORT_FILE=".claude/.session/effort.txt"
if [[ -f "$EFFORT_FILE" ]]; then
  EFFORT=$(cat "$EFFORT_FILE")
  if [[ "$EFFORT" == "low" ]]; then
    INPUT=$(cat)
    STDOUT=$(echo "$INPUT" | jq -r '.tool_output.stdout // empty' | head -n 15)
    STDERR=$(echo "$INPUT" | jq -r '.tool_output.stderr // empty' | head -n 15)
    
    jq -n \
      --arg stdout "$STDOUT" \
      --arg stderr "$STDERR" \
      '{hookSpecificOutput: {updatedToolOutput: {stdout: $stdout, stderr: $stderr}}}'
    exit 0
  fi
fi

echo "{}"
