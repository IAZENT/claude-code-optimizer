show_status() {
  local BASE="$HOME/.claude"
  local check_total=0 check_ok=0

  _chk() {
    local label="$1" path="$2"
    ((check_total++)) || true
    if [[ -e "$path" ]]; then
      local sz; sz=$(wc -c < "$path" 2>/dev/null | tr -d ' ')
      echo -e "  ${GREEN}✔${RESET}  $label  ${DIM}(${sz}b)${RESET}"
      ((check_ok++)) || true
    else
      echo -e "  ${RED}✗${RESET}  $label  ${DIM}→ $(echo "$path" | sed "s|$HOME|~|g")${RESET}"
    fi
  }

  section "Status Report"

  echo -e "  ${BOLD}Global (~/.claude/)${RESET}"
  divider
  _chk "CLAUDE.md"               "$BASE/CLAUDE.md"
  _chk "settings.json"           "$BASE/settings.json"
  _chk "MCP config"              "$BASE/claude_desktop_config.json"
  blank
  _chk "Hook: block-secrets"     "$BASE/hooks/scripts/block-secrets.sh"
  _chk "Hook: block-bash"        "$BASE/hooks/scripts/block-dangerous-bash.sh"
  _chk "Hook: format"            "$BASE/hooks/scripts/format.sh"
  _chk "Hook: pre-compact"       "$BASE/hooks/scripts/pre-compact.sh"
  _chk "Hook: subagent-capture"  "$BASE/hooks/scripts/subagent-capture.sh"
  _chk "Hook: cost-guard"        "$BASE/hooks/scripts/cost-guard.sh"
  _chk "Hook: token-trim"        "$BASE/hooks/scripts/token-trim.sh"
  blank
  _chk "Agent: researcher"       "$BASE/agents/researcher.md"
  _chk "Agent: tester"           "$BASE/agents/tester.md"
  _chk "Agent: reviewer"         "$BASE/agents/reviewer.md"
  blank
  _chk "Command: plan"           "$BASE/commands/plan.md"
  _chk "Command: debug"          "$BASE/commands/debug.md"
  _chk "Command: commit"         "$BASE/commands/commit.md"
  _chk "Command: review"         "$BASE/commands/review.md"
  _chk "Command: refactor"       "$BASE/commands/refactor.md"
  _chk "Command: compress"       "$BASE/commands/compress.md"
  _chk "Command: context"        "$BASE/commands/context.md"
  _chk "Command: new-project"    "$BASE/commands/new-project.md"
  _chk "Command: chain-of-draft" "$BASE/commands/chain-of-draft.md"
  _chk "Command: effort-low"     "$BASE/commands/effort-low.md"
  _chk "Command: effort-high"    "$BASE/commands/effort-high.md"
  _chk "Command: budget-check"   "$BASE/commands/budget-check.md"
  blank
  _chk "Skill: commit-pr"           "$BASE/skills/commit-pr/SKILL.md"
  _chk "Skill: codebase-explainer"  "$BASE/skills/codebase-explainer/SKILL.md"
  _chk "Skill: frontend-aesthetics" "$BASE/skills/frontend-aesthetics/SKILL.md"
  _chk "Skill: lean"                "$BASE/skills/lean/SKILL.md"
  if [[ -f "$BASE/skills/webapp-tester/SKILL.md" ]]; then
    _chk "Skill: webapp-tester"     "$BASE/skills/webapp-tester/SKILL.md"
  fi
  if [[ -f "$BASE/skills/design-system/SKILL.md" ]]; then
    _chk "Skill: design-system"     "$BASE/skills/design-system/SKILL.md"
  fi
  blank
  _chk "Budget config"           "$BASE/budget.conf"
  blank

  echo -e "  ${BOLD}Global command${RESET}"
  divider
  if command -v "$INSTALL_NAME" &>/dev/null; then
    log "$INSTALL_NAME → $(command -v "$INSTALL_NAME")"
    ((check_ok++)) || true
  else
    echo -e "  ${RED}✗${RESET}  $INSTALL_NAME  not in PATH"
    dim     "Fix: $(basename "$SCRIPT_PATH") --install"
  fi
  ((check_total++)) || true
  blank

  echo -e "  ${BOLD}Project (current dir: $(pwd))${RESET}"
  divider
  if [[ -d ".claude" ]]; then
    _chk "CLAUDE.md"              "CLAUDE.md"
    _chk ".claude/settings.json"  ".claude/settings.json"
    _chk ".mcp.json"              ".mcp.json"
    _chk ".claude/MEMORY.md"      ".claude/MEMORY.md"
    _chk "Hook: session-start"    ".claude/hooks/scripts/session-start.sh"
    _chk "Hook: discovery-gate"   ".claude/hooks/scripts/discovery-gate.sh"
    _chk "Hook: quality-gate"     ".claude/hooks/scripts/quality-gate.sh"
    _chk "Hook: token-report"     ".claude/hooks/scripts/token-report.sh"
    _chk "Agent: api-designer"    ".claude/agents/api-designer.md"
    _chk "Command: feature"       ".claude/commands/feature.md"
    _chk "Command: design"        ".claude/commands/design.md"
    _chk "DESIGN.md"              "DESIGN.md"
    _chk "Repomix config"         ".repomix.config.json"
    _chk ".codesightignore"       ".codesightignore"
    _chk "Codebase index"         ".codesight/CONTEXT.md"
    blank
    echo -e "  ${BOLD}Team Pack${RESET}"
    divider
    if [[ -f ".claude/team.config.json" ]]; then
      _chk "Team Config"            ".claude/team.config.json"
      _chk "TEAM.md"                ".claude/TEAM.md"
      _chk "INTERFACES.md"          ".claude/INTERFACES.md"
      _chk "Agent: frontend"        ".claude/agents/frontend-specialist.md"
      _chk "Agent: integration"     ".claude/agents/integration-reviewer.md"
      _chk "Command: team-setup"    ".claude/commands/team-setup.md"
      _chk "Hook: interface-guard"  ".claude/hooks/scripts/interface-guard.sh"
    else
      echo -e "  ${DIM}Team Pack not installed.${RESET}"
    fi
    blank
    echo -e "  ${BOLD}Docs Pack${RESET}"
    divider
    if [[ -d ".claude/docs-pack.installed" || -f ".claude/agents/technical-writer.md" ]]; then
      _chk "Agent: tech-writer"     ".claude/agents/technical-writer.md"
      _chk "Command: docs-init"     ".claude/commands/docs-init.md"
      _chk "Command: docs-sync"     ".claude/commands/docs-sync.md"
      _chk "Command: ticket-gen"    ".claude/commands/ticket-gen.md"
      _chk "docs/MEMORY_BANK.md"    "docs/MEMORY_BANK.md"
      _chk "docs/PRD.md"            "docs/PRD.md"
      _chk "docs/ARCHITECTURE.md"   "docs/ARCHITECTURE.md"
    else
      echo -e "  ${DIM}Docs Pack not installed.${RESET}"
    fi
  else
    echo -e "  ${DIM}No .claude/ in current directory.${RESET}"
    dim "Run from your project root: claude-optimize --project"
  fi
  blank
  divider
  echo -e "  ${DIM}Score: $check_ok / $check_total items configured${RESET}"
  blank
}
