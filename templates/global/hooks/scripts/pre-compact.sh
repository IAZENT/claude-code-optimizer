#!/usr/bin/env bash
# PreCompact — distill session state into MEMORY.md before context wipe
MEMORY_FILE="${CLAUDE_PROJECT_DIR:-.}/.claude/MEMORY.md"
TRANSCRIPT_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/transcripts"
mkdir -p "$TRANSCRIPT_DIR"
[[ -n "${CLAUDE_TRANSCRIPT:-}" ]] && echo "$CLAUDE_TRANSCRIPT" > "$TRANSCRIPT_DIR/$(date +%Y%m%d-%H%M%S).md" 2>/dev/null || true
printf '{"additionalContext":"## Context compacted at %s\nSee .claude/MEMORY.md for session history.\n"}\n' "$(date '+%Y-%m-%d %H:%M')"
exit 0
