#!/usr/bin/env bash
# compact-output.sh — Strips ANSI, dedups, and truncates noisy commands
# Trigger: PostToolUse:Bash

set -euo pipefail

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
STDOUT=$(echo "$INPUT" | jq -r '.tool_output.stdout // empty')
STDERR=$(echo "$INPUT" | jq -r '.tool_output.stderr // empty')

# Function to compact text
compact_text() {
  local text="$1"
  if [[ -z "$text" ]]; then echo ""; return; fi
  
  # Strip ANSI
  text=$(echo "$text" | sed -E 's/\x1B\[[0-9;]*[a-zA-Z]//g' | sed -E 's/\r.*//g')
  
  # Check if command is known noisy
  if echo "$COMMAND" | grep -Eq 'git (log|diff|status|show)|(npm|pnpm|yarn) (test|install|build|run)|pytest|go test|docker build|cargo (build|test)'; then
    # We apply truncation and dedup
    # Preserve signal:
    if echo "$text" | grep -Eiq 'error|fail|traceback|panic|exception'; then
      echo "$text" # Don't aggressively truncate if errors are present
    else
      local line_count=$(echo "$text" | wc -l)
      if (( line_count > 80 )); then
        local head_lines=$(echo "$text" | head -n 40)
        local tail_lines=$(echo "$text" | tail -n 40)
        local omitted=$(( line_count - 80 ))
        text="${head_lines}\n… ${omitted} lines omitted (rerun with --verbose if needed) …\n${tail_lines}"
      fi
      # Basic dedup (optional logic here)
      echo -e "$text"
    fi
  else
    echo "$text"
  fi
}

if [[ "$TOOL_NAME" == "Bash" && -n "$COMMAND" ]]; then
  NEW_STDOUT=$(compact_text "$STDOUT")
  NEW_STDERR=$(compact_text "$STDERR")
  
  # Output the modified tool output format expected by Claude Code
  jq -n \
    --arg stdout "$NEW_STDOUT" \
    --arg stderr "$NEW_STDERR" \
    '{hookSpecificOutput: {updatedToolOutput: {stdout: $stdout, stderr: $stderr}}}'
else
  echo "{}"
fi
