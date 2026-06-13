#!/usr/bin/env bash
# PreCompact — preserve key state before context wipe
TRANSCRIPT_DIR="${CLAUDE_PROJECT_DIR}/.claude/transcripts"
mkdir -p "$TRANSCRIPT_DIR"
[[ -n "${CLAUDE_TRANSCRIPT:-}" ]] && echo "$CLAUDE_TRANSCRIPT" > "$TRANSCRIPT_DIR/$(date +%Y%m%d-%H%M%S).md" 2>/dev/null || true
printf '{"additionalContext":"## Context compacted at %s\nPrior session summary in .claude/MEMORY.md\n"}\n' "$(date '+%Y-%m-%d %H:%M')"
exit 0
