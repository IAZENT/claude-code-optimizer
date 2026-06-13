setup_project() {
  local PROJECT_DIR="${1:-}"

  # ── Resolve project dir ────────────────────────────────────────────────────
  if [[ -n "$PROJECT_DIR" ]]; then
    [[ ! -d "$PROJECT_DIR" ]] && { error "Directory not found: $PROJECT_DIR"; exit 1; }
    cd "$PROJECT_DIR"
  elif $YES_TO_ALL; then
    : # --yes with no --project path → use current directory, no prompt
  else
    blank
    echo -e "  ${BOLD}Project directory${RESET}"
    dim "Press Enter to use: ${BOLD}$(pwd)${RESET}"
    dim "Or type an absolute or relative path."
    blank
    local path_input
    printf "  ${CYAN}▶${RESET} ${BOLD}Path [.]:${RESET} "
    read -r path_input
    path_input="${path_input:-.}"
    if [[ "$path_input" != "." ]]; then
      [[ ! -d "$path_input" ]] && { error "Directory not found: $path_input"; exit 1; }
      cd "$path_input"
    fi
  fi

  local PROJECT_NAME; PROJECT_NAME=$(basename "$(pwd)")
  local BASE=".claude"
  local PTOT=11

  section "Project Setup  ($(pwd))"
  info "Creating project config directories..."
  $DRY_RUN || mkdir -p "$BASE/agents" "$BASE/commands" "$BASE/hooks/scripts" "$BASE/rules" "$BASE/skills"
  log "Directories: .claude/{agents,commands,hooks/scripts,rules,skills}"
  blank

  # Sanity check
  if [[ ! -f "package.json" && ! -f "pyproject.toml" && ! -f "Cargo.toml" && \
        ! -f "go.mod" && ! -f "Gemfile" && ! -d ".git" ]]; then
    warn "No recognizable project file found (package.json, go.mod, .git, etc.)"
    ask_yn "Continue anyway?" "N" || { info "Aborted. cd into your project root first."; exit 0; }
  fi

  # ── Step 1: CLAUDE.md ──────────────────────────────────────────────────────
  step_banner 1 $PTOT "Project CLAUDE.md" "Stack · architecture · dev commands · rules — project-specific context"
  dim "This is the project's context file. Claude reads it at the start of every session."
  dim "EDIT IT before writing any code — replace the placeholders with your actual stack."
  blank
  if want_component "Project CLAUDE.md"; then
    doing "Writing CLAUDE.md..."
    write_template "templates/project/CLAUDE.md" "CLAUDE.md"
  fi

  # ── Step 1b: .claudeignore ──────────────────────────────────────────────────
  step_banner "1b" $PTOT ".claudeignore" "Blocks context bloat — prevents Claude from reading junk directories"
  dim "By default, Claude explores 'node_modules', 'dist', etc. which burns thousands of tokens."
  dim "This explicitly denies access to compiled outputs and caches."
  blank
  if want_component ".claudeignore"; then
    doing "Writing .claudeignore..."
    write_template "templates/project/.claudeignore" ".claudeignore"
  fi

  # ── Step 2: settings.json ──────────────────────────────────────────────────
  step_banner 2 $PTOT "Project settings.json" "Project permissions, hooks, and overrides — commit this file"
  dim "This sets project-level permissions (what Claude can write/run) and hooks"
  dim "(session-start injects codebase map; quality-gate blocks on type errors)."
  blank
  if want_component "Project settings.json"; then
    doing "Writing .claude/settings.json..."
    local sj_mode=""
    [[ -e "$BASE/settings.json" ]] && sj_mode="--merge-json"
    write_template "templates/project/settings.json" "$BASE/settings.json" $sj_mode

    write_template "templates/project/settings.local.json" "$BASE/settings.local.json" --safe
  fi

  # ── Step 3: .mcp.json ──────────────────────────────────────────────────────
  step_banner 3 $PTOT ".mcp.json" "Project-scoped MCP servers — git + optional DB connector"
  dim "Global MCPs (GitHub, Context7, etc.) are already in ~/.claude/claude_desktop_config.json."
  dim "This adds project-specific ones like a database connector. Uncomment what you need."
  blank
  if want_component ".mcp.json"; then
    doing "Writing .mcp.json..."
    local mcp_mode=""
    [[ -e ".mcp.json" ]] && mcp_mode="--merge-json"
    write_template "templates/project/.mcp.json" ".mcp.json" $mcp_mode
  fi

  # ── Step 4: Project hooks ──────────────────────────────────────────────────
  step_banner 4 $PTOT "Project Hooks" "session-start · discovery-gate · quality-gate · pre-compact · subagent-capture"
  dim "session-start: injects the codebase map (.codesight/CONTEXT.md) + MEMORY.md automatically."
  dim "discovery-gate: enforces running codesight before raw file reads (9-13x token saving)."
  dim "quality-gate: runs tsc/mypy/go vet before Claude marks a task complete."
  blank
  if want_component "Project Hooks"; then

    doing "Writing session-start.sh..."
    write_template "templates/project/hooks/scripts/session-start.sh" "$BASE/hooks/scripts/session-start.sh" --safe

    doing "Writing discovery-gate.sh..."
    write_template "templates/project/hooks/scripts/discovery-gate.sh" "$BASE/hooks/scripts/discovery-gate.sh" --safe

    doing "Writing quality-gate.sh..."
    write_template "templates/project/hooks/scripts/quality-gate.sh" "$BASE/hooks/scripts/quality-gate.sh" --safe

    doing "Writing pre-compact.sh (project)..."
    write_template "templates/project/hooks/scripts/pre-compact.sh" "$BASE/hooks/scripts/pre-compact.sh" --safe

    doing "Writing subagent-capture.sh (project)..."
    write_template "templates/project/hooks/scripts/subagent-capture.sh" "$BASE/hooks/scripts/subagent-capture.sh" --safe

    doing "Writing token-report.sh..."
    write_template "templates/project/hooks/scripts/token-report.sh" "$BASE/hooks/scripts/token-report.sh" --safe

    if ! $DRY_RUN; then
      make_exec "$BASE/hooks/scripts/session-start.sh"
      make_exec "$BASE/hooks/scripts/discovery-gate.sh"
      make_exec "$BASE/hooks/scripts/quality-gate.sh"
      make_exec "$BASE/hooks/scripts/pre-compact.sh"
      make_exec "$BASE/hooks/scripts/subagent-capture.sh"
      make_exec "$BASE/hooks/scripts/token-report.sh"
    fi
  fi

  # ── Step 5: Domain agents ──────────────────────────────────────────────────
  step_banner 5 $PTOT "Domain Agents" "api-designer · db-migrator — project-specific specialists"
  dim "Edit these to match your actual domain. An 'api-designer' agent knows your"
  dim "API conventions so you don't have to repeat them every prompt."
  blank
  if want_component "Domain Agents"; then

    doing "Writing api-designer.md..."
    write_template "templates/project/agents/api-designer.md" "$BASE/agents/api-designer.md" --safe

    doing "Writing db-migrator.md..."
    write_template "templates/project/agents/db-migrator.md" "$BASE/agents/db-migrator.md" --safe
  fi

  # ── Step 6: Project commands ───────────────────────────────────────────────
  step_banner 6 $PTOT "Project Commands" "/project:feature (RPIV) · /project:deploy (preflight) · /project:design (DESIGN.md)"
  dim "/project:feature enforces Research → Plan → Implement → Validate workflow."
  dim "This stops Claude from diving into code before understanding the codebase."
  blank
  if want_component "Project Commands"; then

    doing "Writing feature.md..."
    write_template "templates/project/commands/feature.md" "$BASE/commands/feature.md" --safe

    doing "Writing deploy.md..."
    write_template "templates/project/commands/deploy.md" "$BASE/commands/deploy.md" --safe

    doing "Writing design.md (command)..."
    write_template "templates/project/commands/design.md" "$BASE/commands/design.md" --safe
  fi

  # ── Step 7: MEMORY.md + .gitignore ────────────────────────────────────────
  step_banner 7 $PTOT "MEMORY.md + .gitignore" "Session decisions log + .gitignore entries for Claude files"
  dim "MEMORY.md is auto-updated by hooks. Use it to record key decisions,"
  dim "solved bugs, and established patterns — it survives context resets."
  blank
  if want_component "MEMORY.md + .gitignore"; then

    doing "Writing .claude/MEMORY.md..."
    write_template "templates/project/MEMORY.md" "$BASE/MEMORY.md" --safe

    doing "Updating .gitignore..."
    if ! $DRY_RUN; then
      local BLOCK="
# Claude Code (claude-optimize)
.claude/settings.local.json
.claude/MEMORY.md
.claude/transcripts/
.claude/.session/
.mcp.json
.env.claude
.codesight/cache/"
      if [[ -f ".gitignore" ]]; then
        if ! grep -q "settings.local.json" .gitignore 2>/dev/null; then
          echo "$BLOCK" >> .gitignore
          log "Added Claude Code entries to .gitignore"
          TRACK_MODIFIED+=(".gitignore  [+Claude Code entries]")
        else
          skip ".gitignore  (Claude Code entries already present)"
          TRACK_SKIPPED+=(".gitignore  [already has entries]")
        fi
      else
        echo "$BLOCK" > .gitignore
        log "Created .gitignore"
        TRACK_CREATED+=(".gitignore")
      fi
    fi
  fi

  # ── Step 8: DESIGN.md ──────────────────────────────────────────────────────
  step_banner 8 $PTOT "DESIGN.md" "Anti-AI-slop design system — fonts/colors/layout Claude must follow for ALL UI work"
  dim "Without this, Claude defaults to generic output: Inter/Roboto fonts,"
  dim "purple gradients, evenly-spaced cards. The frontend-aesthetics skill"
  dim "(global) reads this file and matches it instead of falling back to defaults."
  dim "Edit the placeholders below, or run /project:design for a guided interview."
  blank
  if want_component "DESIGN.md"; then
    doing "Writing DESIGN.md..."
    write_template "templates/project/DESIGN.md" "DESIGN.md" --safe
  fi

  # ── Step 9: Repomix config + .codesightignore ─────────────────────────────
  step_banner 9 $PTOT "Repomix + Codesight Ignores" ".repomix.config.json · .codesightignore — stop junk from entering context"
  dim "repomix packs your repo into one AI-friendly file for big refactors."
  dim ".repomix.config.json excludes dist/, .next/, *.lock, *.min.js automatically."
  dim ".codesightignore tells codesight to skip build artifacts (same principle)."
  dim "Run: npx repomix  — then pass the output to Claude for full-repo reasoning."
  blank
  if want_component "Repomix + Codesight config"; then

    doing "Writing .repomix.config.json..."
    write_template "templates/project/.repomix.config.json" ".repomix.config.json" --safe

    doing "Writing .codesightignore..."
    write_template "templates/project/.codesightignore" ".codesightignore" --safe

  fi

  # ── Step 10: Smarter quality-gate ─────────────────────────────────────────
  step_banner 10 $PTOT "Quality Gate Update" "Auto-detect Python src root · add Rust check · smarter path detection"
  dim "Updates quality-gate.sh to auto-detect your Python source root instead of"
  dim "hardcoding 'src/' — fixes false positives on projects using app/, or package name."
  blank
  if [[ -f "$BASE/hooks/scripts/quality-gate.sh" ]]; then
    local py_src=""
    for d in src app lib .; do
      [[ -d "$d" ]] && py_src="$d" && break
    done
    py_src="${py_src:-.}"

    if want_component "Quality Gate (smarter Python path)"; then
      doing "Rewriting quality-gate.sh with auto-detected Python path: $py_src..."
      write_template "templates/project/hooks/scripts/quality-gate.sh" "$BASE/hooks/scripts/quality-gate.sh" --force
      make_exec "$BASE/hooks/scripts/quality-gate.sh"
    fi
  else
    info "quality-gate.sh not found — it will be created in project hooks step."
  fi

  # ── Step 11: Git Pre-commit Hook ──────────────────────────────────────────
  if [[ -d ".git" ]]; then
    step_banner 11 $PTOT "Git Pre-commit Hook" "Wire quality-gate and contract-drift to run before git commit"
    dim "This ensures strict compliance before code is ever pushed to the repo."
    blank
    if want_component "Git Pre-commit Hook"; then
      doing "Writing .git/hooks/pre-commit..."
      if ! $DRY_RUN; then
        cat << 'EOF' > .git/hooks/pre-commit
#!/usr/bin/env bash
# Auto-generated by claude-code-optimizer

echo -e "\e[1;36m▶ Running Claude Optimizer Git Hooks...\e[0m"

# 1. Run Quality Gate
if [[ -f ".claude/hooks/scripts/quality-gate.sh" ]]; then
  bash ".claude/hooks/scripts/quality-gate.sh"
  if [[ $? -ne 0 ]]; then
    echo -e "\e[1;31m✗ Quality Gate failed. Commit aborted.\e[0m"
    exit 1
  fi
fi

# 2. Run Contract Drift (Team Pack)
if [[ -f ".claude/hooks/scripts/contract-drift.sh" ]]; then
  bash ".claude/hooks/scripts/contract-drift.sh"
  if [[ $? -ne 0 ]]; then
    echo -e "\e[1;33m⚠ Contract Drift detected. Please check logs.\e[0m"
    # Note: We don't block commit on drift, just warn.
  fi
fi

echo -e "\e[1;32m✔ Claude checks passed.\e[0m"
exit 0
EOF
        chmod +x .git/hooks/pre-commit
        log "Created .git/hooks/pre-commit"
        TRACK_CREATED+=(".git/hooks/pre-commit")
      else
        dry_run_note ".git/hooks/pre-commit  [Git Hooks Integration]"
      fi
    fi
  fi

  blank
  log "${GREEN}${BOLD}Project setup complete in: $(pwd)${RESET}"
  blank
}
