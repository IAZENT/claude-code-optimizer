setup_global() {
  local BASE="$HOME/.claude"
  local GTOT=9  # total steps

  section "Global Setup  (~/.claude/)  — applies to ALL projects"
  info "Creating directories..."
  $DRY_RUN || mkdir -p "$BASE/commands" "$BASE/agents" "$BASE/hooks/scripts"
  log "Directories: ~/.claude/{commands,agents,hooks/scripts}"
  blank

  # ── Step 1: CLAUDE.md ──────────────────────────────────────────────────────
  step_banner 1 $GTOT "CLAUDE.md" "Universal coding rules — style, standards, honesty, semantic triggers"
  dim "This is your global 'constitution' — applies to every project on this machine."
  dim "Project-specific rules go in /your-project/CLAUDE.md (separate file)."
  blank
  if want_component "CLAUDE.md"; then
    doing "Writing ~/.claude/CLAUDE.md..."
    write_template "templates/global/CLAUDE.md" "$BASE/CLAUDE.md" --merge-md
  fi

  # ── Step 2: settings.json ──────────────────────────────────────────────────
  step_banner 2 $GTOT "settings.json" "Model, caching, global permissions, and hook wiring"
  dim "Controls which model Claude uses, what it's allowed to do,"
  dim "and which scripts run before/after file writes and commands."
  blank
  if want_component "settings.json"; then
    doing "Writing ~/.claude/settings.json..."
    local sj_mode=""
    [[ -e "$BASE/settings.json" ]] && sj_mode="--merge-json"
    write_template "templates/global/settings.json" "$BASE/settings.json" $sj_mode
  fi

  # ── Step 3: MCP servers ────────────────────────────────────────────────────
  step_banner 3 $GTOT "MCP Servers" "context7 · github · fetch  (+ optional: playwright, figma, memory, sequential-thinking, time)"
  dim "Each enabled MCP server adds ~500-1000 tokens of tool schema to EVERY"
  dim "session before you ask anything — 2026 guidance is 3-6 active servers max."
  dim "Only context7 + github + fetch are enabled by default (highest value,"
  dim "lowest overhead). The rest are written as _optional_<name> — rename to"
  dim "activate. Run /context to see per-server token cost, /mcp to toggle."
  blank
  if want_component "MCP Servers"; then
    doing "Writing ~/.claude/claude_desktop_config.json..."
    local mcp_mode=""
    [[ -e "$BASE/claude_desktop_config.json" ]] && mcp_mode="--merge-json"
    write_template "templates/global/claude_desktop_config.json" "$BASE/claude_desktop_config.json" $mcp_mode
  fi

  # ── Step 4: Hooks ──────────────────────────────────────────────────────────
  step_banner 4 $GTOT "Safety Hooks" "block-secrets · block-dangerous-bash · auto-format · pre-compact · subagent-capture"
  dim "Hooks are shell scripts that run automatically at key events."
  dim "block-secrets: stops Claude writing API keys into code files."
  dim "block-dangerous-bash: stops 'rm -rf /', 'DROP DATABASE', etc."
  dim "format: auto-runs prettier/black/gofmt after every file write."
  dim "pre-compact: saves session state before context window is wiped."
  blank
  if want_component "Safety Hooks"; then

    doing "Writing block-secrets.sh..."
    write_template "templates/global/hooks/scripts/block-secrets.sh" "$BASE/hooks/scripts/block-secrets.sh" --safe

    doing "Writing block-dangerous-bash.sh..."
    write_template "templates/global/hooks/scripts/block-dangerous-bash.sh" "$BASE/hooks/scripts/block-dangerous-bash.sh" --safe

    doing "Writing format.sh..."
    write_template "templates/global/hooks/scripts/format.sh" "$BASE/hooks/scripts/format.sh" --safe

    doing "Writing pre-compact.sh..."
    write_template "templates/global/hooks/scripts/pre-compact.sh" "$BASE/hooks/scripts/pre-compact.sh" --safe

    doing "Writing subagent-capture.sh..."
    write_template "templates/global/hooks/scripts/subagent-capture.sh" "$BASE/hooks/scripts/subagent-capture.sh" --safe

    doing "Writing cost-guard.sh..."
    write_template "templates/global/hooks/scripts/cost-guard.sh" "$BASE/hooks/scripts/cost-guard.sh" --safe

    doing "Writing token-trim.sh..."
    write_template "templates/global/hooks/scripts/token-trim.sh" "$BASE/hooks/scripts/token-trim.sh" --safe

    doing "Writing read-once.sh..."
    write_template "templates/global/hooks/scripts/read-once.sh" "$BASE/hooks/scripts/read-once.sh" --safe

    doing "Writing compact-output.sh..."
    write_template "templates/global/hooks/scripts/compact-output.sh" "$BASE/hooks/scripts/compact-output.sh" --safe

    doing "Writing effort-gate-pre.sh..."
    write_template "templates/global/hooks/scripts/effort-gate-pre.sh" "$BASE/hooks/scripts/effort-gate-pre.sh" --safe

    doing "Writing effort-gate-post.sh..."
    write_template "templates/global/hooks/scripts/effort-gate-post.sh" "$BASE/hooks/scripts/effort-gate-post.sh" --safe

    if ! $DRY_RUN; then
      make_exec "$BASE/hooks/scripts/block-secrets.sh"
      make_exec "$BASE/hooks/scripts/block-dangerous-bash.sh"
      make_exec "$BASE/hooks/scripts/format.sh"
      make_exec "$BASE/hooks/scripts/pre-compact.sh"
      make_exec "$BASE/hooks/scripts/subagent-capture.sh"
      make_exec "$BASE/hooks/scripts/cost-guard.sh"
      make_exec "$BASE/hooks/scripts/token-trim.sh"
      make_exec "$BASE/hooks/scripts/read-once.sh"
      make_exec "$BASE/hooks/scripts/compact-output.sh"
      make_exec "$BASE/hooks/scripts/effort-gate-pre.sh"
      make_exec "$BASE/hooks/scripts/effort-gate-post.sh"
    fi
  fi

  # ── Step 5: Subagents ──────────────────────────────────────────────────────
  step_banner 5 $GTOT "Subagents" "researcher (Haiku) · tester (Haiku) · reviewer (Sonnet)"
  dim "Subagents are mini Claude instances that run separate from your main session."
  dim "researcher + tester use the 10x-cheaper Haiku model — saves significant quota."
  dim "They're triggered automatically by keywords like 'explore', 'run tests', 'review'."
  blank
  if want_component "Subagents"; then

    doing "Writing researcher.md..."
    write_template "templates/global/agents/researcher.md" "$BASE/agents/researcher.md" --safe

    doing "Writing tester.md..."
    write_template "templates/global/agents/tester.md" "$BASE/agents/tester.md" --safe

    doing "Writing reviewer.md..."
    write_template "templates/global/agents/reviewer.md" "$BASE/agents/reviewer.md" --safe
  fi

  # ── Step 6: Commands ───────────────────────────────────────────────────────
  step_banner 6 $GTOT "Slash Commands" "/plan /debug /commit /review /refactor /compress /context /new-project"
  dim "These become available as /user:name in Claude Code."
  dim "They inject structured prompts to enforce workflows — saving you from"
  dim "typing long instructions every time."
  blank
  if want_component "Slash Commands"; then

    doing "Writing plan.md..."
    write_template "templates/global/commands/plan.md" "$BASE/commands/plan.md" --safe

    doing "Writing debug.md..."
    write_template "templates/global/commands/debug.md" "$BASE/commands/debug.md" --safe

    doing "Writing commit.md..."
    write_template "templates/global/commands/commit.md" "$BASE/commands/commit.md" --safe

    doing "Writing review.md..."
    write_template "templates/global/commands/review.md" "$BASE/commands/review.md" --safe

    doing "Writing refactor.md..."
    write_template "templates/global/commands/refactor.md" "$BASE/commands/refactor.md" --safe

    doing "Writing compress.md..."
    write_template "templates/global/commands/compress.md" "$BASE/commands/compress.md" --safe

    doing "Writing context.md..."
    write_template "templates/global/commands/context.md" "$BASE/commands/context.md" --safe

    doing "Writing new-project.md..."
    write_template "templates/global/commands/new-project.md" "$BASE/commands/new-project.md" --safe

    doing "Writing handoff.md..."
    write_template "templates/global/commands/handoff.md" "$BASE/commands/handoff.md" --safe

    doing "Writing claude-md-audit.md..."
    write_template "templates/global/commands/claude-md-audit.md" "$BASE/commands/claude-md-audit.md" --safe

    doing "Writing caveman-claude-md.md..."
    write_template "templates/global/commands/caveman-claude-md.md" "$BASE/commands/caveman-claude-md.md" --safe
  fi

  # ── Step 6b: Token Economy Commands (v1.0.0) ─────────────────────────────────
  #   These commands give real-time control over token usage and reasoning effort.
  #   All available as /user:<name> in Claude Code.

    doing "Writing chain-of-draft.md..."
    write_template "templates/global/commands/chain-of-draft.md" "$BASE/commands/chain-of-draft.md" --safe

    doing "Writing effort-low.md..."
    write_template "templates/global/commands/effort-low.md" "$BASE/commands/effort-low.md" --safe

    doing "Writing effort-high.md..."
    write_template "templates/global/commands/effort-high.md" "$BASE/commands/effort-high.md" --safe

    doing "Writing budget-check.md..."
    write_template "templates/global/commands/budget-check.md" "$BASE/commands/budget-check.md" --safe

  # ── Step 7: Skills ───────────────────────────────────────────────────────
  step_banner 7 $GTOT "Skills" "commit-pr · codebase-explainer · frontend-aesthetics — anti-AI-slop design defaults"
  dim "Skills live in ~/.claude/skills/<name>/SKILL.md and are auto-discovered."
  dim "Claude loads them on demand based on the 'description' field — unlike"
  dim "slash commands, no /name typing is required, and they can bundle scripts"
  dim "and reference files alongside the prompt."
  blank
  if want_component "Skills"; then

    doing "Writing skills/commit-pr/SKILL.md..."
    write_template "templates/global/skills/commit-pr/SKILL.md" "$BASE/skills/commit-pr/SKILL.md" --safe

    doing "Writing skills/codebase-explainer/SKILL.md..."
    write_template "templates/global/skills/codebase-explainer/SKILL.md" "$BASE/skills/codebase-explainer/SKILL.md" --safe

    doing "Writing skills/frontend-aesthetics/SKILL.md..."
    write_template "templates/global/skills/frontend-aesthetics/SKILL.md" "$BASE/skills/frontend-aesthetics/SKILL.md" --safe

    doing "Writing skills/README.md..."
    write_template "templates/global/skills/README.md" "$BASE/skills/README.md" --safe

    doing "Writing skills/lean/SKILL.md..."
    $DRY_RUN || mkdir -p "$BASE/skills/lean"
    write_template "templates/global/skills/lean/SKILL.md" "$BASE/skills/lean/SKILL.md" --safe

    doing "Writing skills/caveman/SKILL.md..."
    $DRY_RUN || mkdir -p "$BASE/skills/caveman"
    write_template "templates/global/skills/caveman/SKILL.md" "$BASE/skills/caveman/SKILL.md" --safe
  fi

  # ── Step 8: Token Economy Config ──────────────────────────────────────────
  step_banner 8 $GTOT "Token Economy" "budget.conf · ccusage install hint · daily spend alias"
  dim "Sets your daily token budget ceiling used by the cost-guard hook."
  dim "The budget.conf file is read by cost-guard.sh at every PostToolUse event."
  dim "ccusage is a free npm CLI for granular session analytics (optional)."
  blank
  if want_component "Token Economy Config"; then
    local budget_val
    if $YES_TO_ALL; then
      budget_val="$DAILY_BUDGET_DEFAULT"
    else
      printf "  ${CYAN}▶${RESET} ${BOLD}Daily token budget [default: %d]:${RESET} " "$DAILY_BUDGET_DEFAULT"
      read -r budget_val
      budget_val="${budget_val:-$DAILY_BUDGET_DEFAULT}"
      [[ ! "$budget_val" =~ ^[0-9]+$ ]] && { warn "Invalid — using $DAILY_BUDGET_DEFAULT"; budget_val="$DAILY_BUDGET_DEFAULT"; }
    fi

    if ! $DRY_RUN; then
      echo "$budget_val" > "$BASE/budget.conf"
      log "Budget config → ~/.claude/budget.conf  (${budget_val} tokens/day)"
    else
      dry_run_note "~/.claude/budget.conf  [${budget_val} tokens/day]"
    fi

    blank
    info "Optional: install ccusage for detailed session analytics (free, npm)"
    bullet "npm install -g ccusage    ← then run: ccusage today"
    bullet "Or use: /user:budget-check  ← built-in estimate (no install needed)"
    blank

    # Add shell alias hint to .bashrc/.zshrc
    local added_alias=false
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
      if [[ -f "$rc" ]] && ! grep -q "alias claude-budget" "$rc" 2>/dev/null; then
        if ! $DRY_RUN; then
          printf '\n# claude-optimize: quick token budget check\nalias claude-budget="cat ~/.claude/budget.conf 2>/dev/null | xargs -I{} echo \"Daily budget: {} tokens\""\n' >> "$rc"
          log "Added claude-budget alias to $rc"
          added_alias=true
        fi
      fi
    done
    $added_alias || skip "budget alias already in shell rc"
  fi

  # ── Step 9: Wire v1.0.0 hooks into settings.json ────────────────────────────
  step_banner 9 $GTOT "Hook Wiring" "Wire cost-guard + token-trim into global settings.json"
  dim "cost-guard runs on every PostToolUse to check token burn rate."
  dim "token-trim runs on PreCompact to prune MEMORY.md before context wipe."
  dim "If you chose 'skip' on settings.json earlier, run --upgrade to add these."
  blank
  if [[ -f "$BASE/settings.json" ]] && $JQ_AVAILABLE; then
    local has_costguard
    has_costguard=$(jq -r '.. | strings | select(contains("cost-guard"))' "$BASE/settings.json" 2>/dev/null || echo "")
    if [[ -z "$has_costguard" ]]; then
      if ! $DRY_RUN; then
        local merged
        merged=$(jq '
          .hooks.PostToolUse //= [] |
          .hooks.PostToolUse += [{"matcher":"*","hooks":[{"type":"command","command":"~/.claude/hooks/scripts/cost-guard.sh"}]}] |
          .hooks.PreCompact //= [] |
          .hooks.PreCompact += [{"hooks":[{"type":"command","command":"~/.claude/hooks/scripts/token-trim.sh"}]}]
        ' "$BASE/settings.json" 2>/dev/null) && echo "$merged" > "$BASE/settings.json"
        log "Wired cost-guard + token-trim into ~/.claude/settings.json"
      else
        dry_run_note "~/.claude/settings.json  [+cost-guard + token-trim hooks]"
      fi
    else
      skip "settings.json  (cost-guard already wired)"
    fi
  else
    if ! $JQ_AVAILABLE; then
      warn "jq not found — skipping hook wiring. Install jq then re-run: claude-optimize --upgrade"
    else
      info "settings.json not found — hooks will be wired when settings.json is created."
    fi
  fi

  blank
  log "${GREEN}${BOLD}Global setup complete.${RESET}"
  blank
}
