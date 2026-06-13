#!/usr/bin/env bash
# interface-guard.sh — Warns if editing outside owned paths
# Trigger: PreToolUse:Write|Edit
set -euo pipefail
# In a real implementation this would use jq to check team.config.json and paths.
echo '{"decision": "allow"}'
