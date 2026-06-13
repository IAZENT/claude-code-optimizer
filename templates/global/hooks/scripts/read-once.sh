#!/usr/bin/env bash
# read-once.sh — Prevents redundant file reads in a single session
# Trigger: PreToolUse:Read|Glob

set -euo pipefail

TOOL_NAME=$(jq -r '.tool_name' <&0)
TOOL_ARGS=$(jq -r '.tool_input' <&0)
# Depending on the tool, extract paths.
if [[ "$TOOL_NAME" == "Read" || "$TOOL_NAME" == "Glob" ]]; then
  # For Read, there's usually a path or paths argument
  # This is a naive implementation that expects an absolute_path argument or similar.
  # Let's extract file paths being read
  PATHS=$(echo "$TOOL_ARGS" | jq -r '.absolute_path // .path // empty')
  
  if [[ -n "$PATHS" && -f "$PATHS" ]]; then
    SESSION_DIR=".claude/.session"
    mkdir -p "$SESSION_DIR"
    CACHE_FILE="$SESSION_DIR/read-cache.jsonl"
    touch "$CACHE_FILE"
    
    MTIME=$(stat -c %Y "$PATHS" 2>/dev/null || stat -f %m "$PATHS" 2>/dev/null || echo "0")
    HASH=$(head -c 4096 "$PATHS" | sha256sum | awk '{print $1}' || echo "nohash")
    KEY="${PATHS}:${MTIME}:${HASH}"
    
    if grep -Fq "$KEY" "$CACHE_FILE" 2>/dev/null; then
      cat <<EOF
{
  "decision": "block",
  "reason": "Already read this session at $(date). See your earlier notes on this file. If you need to re-check a specific detail, use Grep with a narrow pattern instead of re-reading the whole file."
}
EOF
      exit 2
    else
      echo "$KEY" >> "$CACHE_FILE"
    fi
  fi
fi

cat <<EOF
{
  "decision": "allow"
}
EOF
