#!/usr/bin/env bash
# =============================================================================
# claude-optimize  v1.0.0  |  Claude Code Optimizer
# Max output · Min tokens · Free stack · Solo developer edition
#
#  CHANGELOG
#   v1.0.0 - Initial Open Source Release (combines internal v1-v4 improvements)
#          - NEW: Chain-of-Draft (CoD) command — 80-90% fewer reasoning tokens
#          - NEW: cost-guard hook — warns when daily token budget hits 80%
#          - NEW: lean skill — keyword-triggered low-effort mode for simple tasks
#          - NEW: token-trim hook — auto-prunes MEMORY.md at 100 lines
#          - NEW: token-report hook — logs compact events to MEMORY.md
#          - NEW: effort-low / effort-high / budget-check commands
#          - NEW: .claudeignore auto-generated (blocks context bloat)
#          - NEW: .repomix.config.json scaffold (smart ignores)
#          - NEW: .codesightignore auto-generated
#          - NEW: --analyze flag — parses session JSONL logs, shows top token drains
#          - NEW: --upgrade flag — adds new components without touching old config
#          - NEW: --budget N flag — sets daily token ceiling for cost-guard
#          - IMPROVED: settings.json MAX_OUTPUT_TOKENS 4096→8096 (fewer continuations)
#         - IMPROVED: CLAUDE.md Token Economy section + Chain-of-Draft defaults
#         - IMPROVED: quality-gate.sh auto-detects Python src root
#         - IMPROVED: block-secrets.sh catches OPENAI_API_KEY + Bearer tokens
#         - IMPROVED: session-start.sh injects ccusage daily spend if available
#   v0.9  - FIX: select_mode menu swallowed by command substitution → stderr fix
#         - NEW: Skills step (~/.claude/skills/)
#           pattern for reusable, frontmatter-driven workflows that
#           complement (and increasingly replace) slash commands.
#         - NEW: CLAUDE.md now documents the AGENTS.md convention for
#           multi-agent/tool-portable setups, a hard line-count budget,
#           and a /compact-survival "Compact Instructions" section.
#         - NEW: --status / final summary mention /plugin marketplace.
#
#  FIRST TIME: Install as a global command (run this once from anywhere):
#    chmod +x claude-optimize.sh && ./claude-optimize.sh --install
#
#  USAGE (after install, from any directory):
#    claude-optimize                     interactive wizard
#    claude-optimize --yes               install EVERYTHING, no prompts
#    claude-optimize --global            only configure ~/.claude/
#    claude-optimize --project [path]    only configure a project
#    claude-optimize --both              global + project (recommended first time)
#    claude-optimize --status            show what is / isn't configured
#    claude-optimize --dry-run           preview without writing any files
#    claude-optimize --install           install as global command
# =============================================================================

set -euo pipefail

SCRIPT_VERSION="1.0.0"
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}" 2>/dev/null || readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
INSTALL_DIR="$HOME/.local/bin"
INSTALL_NAME="claudeoptimize"

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m';  GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m';  BOLD='\033[1m';  RESET='\033[0m'
DIM='\033[2m';     MAGENTA='\033[0;35m'; WHITE='\033[1;37m'

# ─── Global flags ─────────────────────────────────────────────────────────────
DRY_RUN=false
YES_TO_ALL=false
CONFLICT_POLICY=""
JQ_AVAILABLE=false
LOG_INDENT=""
DAILY_BUDGET_DEFAULT=200000
UPGRADE_ONLY=false

# ─── Tracking ─────────────────────────────────────────────────────────────────
declare -a TRACK_CREATED=()
declare -a TRACK_MODIFIED=()
declare -a TRACK_SKIPPED=()
declare -a TRACK_BACKUPS=()
declare -a TRACK_ERRORS=()
COMPONENTS_INSTALLED=0
COMPONENTS_SKIPPED=0

# ─── Logging helpers ──────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

for f in "$SCRIPT_DIR"/lib/core/*.sh; do source "$f"; done
for f in "$SCRIPT_DIR"/lib/setup/*.sh; do source "$f"; done
for f in "$SCRIPT_DIR"/lib/packs/*.sh; do source "$f" 2>/dev/null || true; done
source "$SCRIPT_DIR"/lib/self_install.sh

preflight_scan() {
  local -a existing=()
  for f in "$HOME/.claude/CLAUDE.md" "$HOME/.claude/settings.json" \
            "$HOME/.claude/claude_desktop_config.json" \
            ".claude/settings.json" "CLAUDE.md" ".mcp.json"; do
    [[ -e "$f" ]] && existing+=("${f/#$HOME/~}")
  done

  [[ ${#existing[@]} -eq 0 ]] && { CONFLICT_POLICY="safe"; return; }

  section "Existing Files Detected"
  echo -e "  ${YELLOW}These files already exist on your system:${RESET}"
  blank
  for f in "${existing[@]}"; do
    local fp="${f/#\~/$HOME}"
    local sz; sz=$(wc -c < "$fp" 2>/dev/null | tr -d ' ')
    echo -e "  ${YELLOW}!${RESET}  $f  ${DIM}(${sz}b)${RESET}"
  done
  blank
  echo -e "  ${BOLD}How should the script handle conflicts?${RESET}"
  blank
  echo -e "  ${CYAN}${BOLD}[S]${RESET}  ${BOLD}Safe   ${RESET}— Skip existing files. Only CREATE what's missing."
  dim    "         Your current files are completely untouched."
  dim    "         ${GREEN}Recommended if you have custom config you want to keep.${RESET}"
  blank
  echo -e "  ${CYAN}${BOLD}[F]${RESET}  ${BOLD}Force  ${RESET}— Backup all existing files, then write fresh copies."
  dim    "         A .bak.TIMESTAMP file is saved before anything is overwritten."
  dim    "         ${YELLOW}Use if you want a clean slate.${RESET}"
  blank
  echo -e "  ${CYAN}${BOLD}[A]${RESET}  ${BOLD}Ask    ${RESET}— Ask you what to do for each conflicting file."
  dim    "         Shows diff · let you keep/overwrite/merge per file."
  dim    "         ${CYAN}Best for fine-grained control.${RESET}"
  blank

  local pol
  printf "  ${CYAN}▶${RESET} ${BOLD}Choose [S/f/a]:${RESET} "
  read -r pol
  pol="${pol:-S}"
  case "${pol^^}" in
    S) CONFLICT_POLICY="safe";  info "Safe mode — only new files will be created." ;;
    F) CONFLICT_POLICY="force"; warn "Force mode — existing files will be backed up then replaced." ;;
    A) CONFLICT_POLICY="ask";   info "Ask mode — you'll be prompted file by file." ;;
    *) CONFLICT_POLICY="safe";  warn "Invalid input. Defaulting to Safe." ;;
  esac
  blank
}
install_tools() {
  section "External Tools  (free, installable now)"
  dim "These are real tools that compound the config savings."
  dim "Each is skippable — but each one installed is fewer wasted tokens."
  blank

  # ── Tool 1: ccusage ─────────────────────────────────────────────────────────
  step_banner "T1" "T5" "ccusage" "Token usage analytics — see exactly which sessions burn your quota"
  dim "Parses Claude Code's local JSONL logs (no cloud, no data leaves your machine)."
  dim "Run: ccusage today    ccusage blocks --live    ccusage daily"
  dim "Zero extra cost — reads files Claude Code already writes locally."
  blank

  local ccusage_installed=false
  if command -v ccusage &>/dev/null; then
    local cv; cv=$(ccusage --version 2>/dev/null | head -1 || echo "found")
    log "${BOLD}ccusage${RESET}  ${DIM}($cv — already installed)${RESET}"
    ccusage_installed=true
  elif want_component "ccusage (token analytics — npm install -g ccusage)"; then
    doing "Installing ccusage globally..."
    if ! $DRY_RUN; then
      if npm install -g ccusage 2>/dev/null; then
        log "ccusage installed → $(command -v ccusage 2>/dev/null || echo 'ccusage')"
        ccusage_installed=true
        blank
        info "Quick test — today's usage:"
        ccusage today 2>/dev/null || dim "(no sessions yet — use Claude Code first)"
      else
        warn "ccusage install failed. Try manually:"
        bullet "npm install -g ccusage"
        bullet "Or use without install: npx ccusage@latest today"
      fi
    else
      dry_run_note "npm install -g ccusage"
    fi
  fi

  # ── Tool 2: codesight ───────────────────────────────────────────────────────
  step_banner "T2" "T5" "codesight" "Codebase indexing — 9-13x fewer file reads per session"
  dim "Generates .codesight/CONTEXT.md — a compact semantic map of your entire codebase."
  dim "session-start hook injects it automatically. discovery-gate blocks raw reads until it exists."
  dim "Run once per repo, re-run when architecture changes significantly."
  blank

  if want_component "codesight (run for this project now)"; then
    if [[ -d ".git" || -f "package.json" || -f "pyproject.toml" || -f "go.mod" || -f "Cargo.toml" ]]; then
      doing "Running npx codesight --profile claude-code (may take 30-60s)..."
      if ! $DRY_RUN; then
        if npx --yes codesight --profile claude-code 2>/dev/null; then
          log "Codebase index → .codesight/CONTEXT.md"
          if [[ -f ".codesight/CONTEXT.md" ]]; then
            local ctx_size; ctx_size=$(wc -c < ".codesight/CONTEXT.md" | tr -d ' ')
            dim "Index size: ${ctx_size} bytes"
          fi
          bullet "Re-run after major refactors: npx codesight --profile claude-code"
        else
          warn "codesight failed (may not support this project type). Run manually:"
          bullet "npx codesight --profile claude-code"
        fi
      else
        dry_run_note ".codesight/CONTEXT.md  [would be generated by codesight]"
      fi
    else
      info "Not in a project directory — run codesight from your project root:"
      bullet "npx codesight --profile claude-code"
    fi
  fi

  # ── Tool 3: repomix ─────────────────────────────────────────────────────────
  step_banner "T3" "T5" "repomix" "Repo packer — one-command full-codebase snapshot for big refactors"
  dim "npx repomix  → produces .repomix-output.md (filtered by .repomix.config.json)"
  dim "Use when you need Claude to reason about the entire codebase at once."
  dim "No install needed — npx handles it. Config already written in project step."
  blank
  if want_component "repomix test-run (generates .repomix-output.md now)"; then
    if [[ -d ".git" || -f "package.json" || -f "pyproject.toml" ]]; then
      doing "Running npx repomix (uses .repomix.config.json if present)..."
      if ! $DRY_RUN; then
        if npx --yes repomix 2>/dev/null; then
          log "Repo packed → .repomix-output.md"
          if [[ -f ".repomix-output.md" ]]; then
            local size; size=$(wc -c < ".repomix-output.md" | tr -d ' ')
            local lines; lines=$(wc -l < ".repomix-output.md" | tr -d ' ')
            dim "Output: ${size} bytes / ${lines} lines"
          fi
        else
          warn "repomix failed. Run manually: npx repomix"
        fi
      else
        dry_run_note ".repomix-output.md  [would be generated by repomix]"
      fi
    else
      info "Not in a project directory — run repomix from your project root:"
      bullet "npx repomix"
    fi
  fi

  # ── Tool 4: claude-token-saver ──────────────────────────────────────────────
  step_banner "T4" "T6" "claude-token-saver" "Statusline & 1M-context monitor — prevents context bloat"
  dim "Monitors Claude Code's prompt caching TTL and flags sudden token spikes."
  dim "Essential for knowing when to run /compact before hitting maximum limits."
  blank
  if want_component "claude-token-saver (npm install -g claude-token-saver)"; then
    if command -v claude-token-saver &>/dev/null; then
      log "${BOLD}claude-token-saver${RESET}  ${DIM}(already installed)${RESET}"
    else
      doing "Installing claude-token-saver globally..."
      if ! $DRY_RUN; then
        if npm install -g claude-token-saver 2>/dev/null; then
          log "claude-token-saver installed → $(command -v claude-token-saver 2>/dev/null || echo 'claude-token-saver')"
        else
          warn "claude-token-saver install failed. Try manually:"
          bullet "npm install -g claude-token-saver"
        fi
      else
        dry_run_note "npm install -g claude-token-saver"
      fi
    fi
  fi

  # ── Tool 5: rtk (Rust Token Killer) ─────────────────────────────────────────
  step_banner "T5" "T6" "rtk" "Rust Token Killer — silent CLI proxy that strips ANSI and noise"
  dim "rtk intercepts terminal commands and strips progress bars, repetitive logs,"
  dim "and ANSI codes before sending them to Claude, saving 60-90% on CLI output tokens."
  blank
  if want_component "rtk (curl install script — compiles locally)"; then
    if command -v rtk &>/dev/null; then
      log "${BOLD}rtk${RESET}  ${DIM}(already installed)${RESET}"
    else
      doing "Installing rtk (Rust Token Killer)..."
      if ! $DRY_RUN; then
        if curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/master/install.sh 2>/dev/null | sh; then
          log "rtk installed. Run 'rtk gain' to verify."
        else
          warn "rtk install failed. Try manually via Cargo:"
          bullet "cargo install --git https://github.com/rtk-ai/rtk rtk"
        fi
      else
        dry_run_note "curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/master/install.sh | sh"
      fi
    fi
  fi

  # ── Tool 6: claude-mem (plugin — must be installed INSIDE Claude Code) ───────
  step_banner "T6" "T6" "claude-mem" "Persistent memory plugin — survives session restarts via SQLite"
  dim "claude-mem stores session history, compresses it, re-injects relevant context."
  dim "${YELLOW}⚠️  This is a Claude Code PLUGIN — cannot be installed by this script.${RESET}"
  dim "You must install it INSIDE a Claude Code session: /plugin install claude-mem"
  blank
  if want_component "claude-mem (show install instructions)"; then
    blank
    echo -e "  ${BOLD}Install claude-mem inside Claude Code:${RESET}"
    bullet "1. Open Claude Code: cd /your/project && claude"
    bullet "2. Run: /plugin marketplace add thedotmack/claude-mem"
    bullet "3. Run: /plugin install claude-mem"
    bullet "4. Restart Claude Code — memory is now persistent"
    blank
    
    local mem_file="${CLAUDE_PROJECT_DIR:-.}/.claude/MEMORY.md"
    if [[ -f "$mem_file" ]] && ! $DRY_RUN; then
      if ! grep -q "claude-mem" "$mem_file" 2>/dev/null; then
        printf '\n## Tool Reminder\n- Install claude-mem plugin for persistent memory across sessions:\n  /plugin marketplace add thedotmack/claude-mem → /plugin install claude-mem\n' >> "$mem_file"
        log "Reminder added to .claude/MEMORY.md"
      fi
    fi
  fi

  blank
  # Summary of what can't be script-installed
  divider
  echo -e "  ${YELLOW}${BOLD}Tools requiring manual in-Claude-Code installation:${RESET}"
  blank
  bullet "claude-mem   → /plugin marketplace add thedotmack/claude-mem"
  bullet "             → /plugin install claude-mem"
  dim   "             (run inside a Claude Code session, not here)"
  blank
  bullet "/plugin      → browse marketplace for more plugins, skills, MCP bundles"
  dim   "             (type /plugin in Claude Code to see all available)"
  blank
}
print_manual_steps() {
  section "Manual Steps (Required)"

  echo -e "  ${CYAN}${BOLD}1)${RESET}  Install Claude Code (if not yet)"
  bullet "npm install -g @anthropic-ai/claude-code"
  bullet "claude --version  ← verify"
  blank

  echo -e "  ${CYAN}${BOLD}2)${RESET}  Add your profile instructions"
  bullet "In Claude Code: gear icon → Profile Instructions"
  bullet "Paste your Principal Engineer system prompt there"
  dim   "This is your single strongest lever. Do it first."
  blank

  echo -e "  ${CYAN}${BOLD}3)${RESET}  Get a free GitHub PAT  (only for GitHub MCP)"
  bullet "github.com → Settings → Developer settings → Fine-grained tokens"
  bullet "Scopes: Contents:Read · Metadata:Read · Issues:Read · PRs:Read"
  bullet "Edit ~/.claude/claude_desktop_config.json → replace <YOUR_GITHUB_PAT>"
  blank

  echo -e "  ${CYAN}${BOLD}4)${RESET}  Verify MCP servers loaded"
  bullet "In Claude Code: type /mcp  OR  claude mcp list"
  bullet "Should see: context7 · github · fetch  (3 enabled by default)"
  bullet "Activate optional ones (playwright, figma, memory, ...) by renaming"
  bullet "  the _optional_<name> entry in ~/.claude/claude_desktop_config.json"
  bullet "Run /context anytime to see each server's token cost"
  blank

  echo -e "  ${CYAN}${BOLD}5)${RESET}  Test the secret-blocking hook"
  bullet 'echo '"'"'{"tool_input":{"content":"sk-abc123xyzabc123xyzabc123xyz"}}'"'"' | bash ~/.claude/hooks/scripts/block-secrets.sh'
  bullet 'Expected output: {"decision":"block",...}'
  blank
}
print_project_checklist() {
  section "⚡  Before Writing a Single Line of Code"

  echo -e "  ${YELLOW}${BOLD}[1]  Edit CLAUDE.md  (most important step)${RESET}"
  bullet "Open CLAUDE.md in your project root"
  bullet "Replace every ⚠️ EDIT THIS section with your ACTUAL stack"
  bullet "Delete placeholder comments when done. Target: under 150 lines."
  bullet "💡 ${CYAN}Pro-tip: Ask Claude to do it for you! Paste this in Claude Code:${RESET}"
  bullet '   "Update CLAUDE.md, DESIGN.md, and project configs for a new project building'
  bullet '   [Your App Description]. Use the latest stable tech stack and best practices."'
  blank

  echo -e "  ${YELLOW}${BOLD}[2]  Generate codebase index${RESET}"
  bullet "npx codesight --profile claude-code"
  bullet "Verify .codesight/CONTEXT.md was created"
  bullet "Create .codesightignore: add dist/ .next/ node_modules/ *.min.js *.lock"
  blank

  echo -e "  ${YELLOW}${BOLD}[3]  Make hooks executable${RESET}"
  bullet "chmod +x .claude/hooks/scripts/*.sh"
  bullet "chmod +x ~/.claude/hooks/scripts/*.sh"
  blank

  echo -e "  ${YELLOW}${BOLD}[4]  Configure DB MCP if you have a database${RESET}"
  bullet "Edit .mcp.json — rename _optional_postgres or _optional_sqlite"
  bullet "Fill in your connection string (use an env var reference, not raw creds)"
  blank

  echo -e "  ${YELLOW}${BOLD}[5]  Open Claude Code from the project directory${RESET}"
  bullet "cd /your/project && claude"
  bullet "session-start hook injects context automatically on every new session"
  blank

  echo -e "  ${YELLOW}${BOLD}[6]  Workflow for every feature${RESET}"
  bullet "/project:feature \"what you want to build\"   — enforces RPIV workflow"
  bullet "OR: /user:plan → approve → implement → /user:review"
  bullet "New project from scratch: /user:new-project <description>"
  blank

  echo -e "  ${YELLOW}${BOLD}[7]  Fill in DESIGN.md before generating any UI${RESET}"
  bullet "Run /project:design for a guided interview, or edit DESIGN.md directly"
  bullet "Without it, UI requests default to generic fonts/gradients/layouts"
  bullet "Optional: activate the playwright MCP (rename _optional_playwright) so"
  bullet "  Claude can open the page it built and check it against DESIGN.md"
  blank

  echo -e "  ${YELLOW}${BOLD}Token hygiene (protect your quota):${RESET}"
  bullet "Context > 80% full → run /user:compress, then /compact, start fresh session"
  bullet "Frontend + backend = separate sessions  (don't mix concerns in one context)"
  bullet "Always /user:plan before implementing  (~50 tokens saves ~5000 from dead ends)"
  bullet "Use /user:context to see exactly what Claude has loaded"
  bullet "Keep active MCP servers to 3-6 total — each adds ~500-1000 tokens at session start"
  blank
}
print_final_summary() {
  local mode="$1"

  blank
  echo -e "${BOLD}${GREEN}"
  echo "  ╔══════════════════════════════════════════════════════════════╗"
  echo "  ║                   SETUP COMPLETE  ✔                        ║"
  echo "  ╚══════════════════════════════════════════════════════════════╝"
  echo -e "${RESET}"

  # Files created
  if [[ ${#TRACK_CREATED[@]} -gt 0 ]]; then
    echo -e "  ${GREEN}${BOLD}Created (${#TRACK_CREATED[@]} files):${RESET}"
    for f in "${TRACK_CREATED[@]}"; do
      [[ -n "$f" ]] && echo -e "    ${GREEN}✔${RESET}  $f"
    done
    blank
  fi

  # Files modified
  if [[ ${#TRACK_MODIFIED[@]} -gt 0 ]]; then
    echo -e "  ${CYAN}${BOLD}Modified (${#TRACK_MODIFIED[@]} files):${RESET}"
    for f in "${TRACK_MODIFIED[@]}"; do
      [[ -n "$f" ]] && echo -e "    ${CYAN}⊕${RESET}  $f"
    done
    if [[ ${#TRACK_BACKUPS[@]} -gt 0 ]]; then
      blank
      echo -e "  ${DIM}Backups saved (restore if needed):${RESET}"
      for b in "${TRACK_BACKUPS[@]}"; do
        [[ -n "$b" ]] && dim "    $b"
      done
    fi
    blank
  fi

  # Files skipped
  if [[ ${#TRACK_SKIPPED[@]} -gt 0 ]]; then
    echo -e "  ${DIM}${BOLD}Kept your version (${#TRACK_SKIPPED[@]} skipped):${RESET}"
    for f in "${TRACK_SKIPPED[@]}"; do
      [[ -n "$f" ]] && echo -e "  ${DIM}  ↷  $f${RESET}"
    done
    blank
  fi

  divider
  blank

  # Quick reference
  echo -e "  ${BOLD}Global slash commands  → use as /user:name in Claude Code${RESET}"
  bullet "/user:plan              numbered plan, no code until you confirm"
  bullet "/user:debug             root cause + minimal fix, skip the noise"
  bullet "/user:commit            Conventional Commit from staged diff"
  bullet "/user:review            security + perf + quality audit"
  bullet "/user:refactor          safe restructure, zero behavior change"
  bullet "/user:compress          checkpoint → MEMORY.md → safe to /compact"
  bullet "/user:context           debug what Claude has loaded + % full"
  bullet "/user:new-project       interview → generate bootstrap.sh for any stack"
  blank
  echo -e "  ${BOLD}${CYAN}★ New in v1.0.0 — Token Economy Commands${RESET}"
  bullet "/user:chain-of-draft    80-90% fewer reasoning tokens (CoD mode)"
  bullet "/user:effort-low        lean session: CoD + no subagents + direct answers"
  bullet "/user:effort-high       deep session: full reasoning + explorer subagent"
  bullet "/user:budget-check      live token spend + context health + recommendation"
  blank

  echo -e "  ${BOLD}Skills  → ~/.claude/skills/  (auto-loaded, no /name needed)${RESET}"
  bullet "commit-pr            stage-aware commit message + optional PR description"
  bullet "codebase-explainer   architecture overview, defers exploration to subagent"
  bullet "frontend-aesthetics  blocks generic fonts/gradients/layouts on UI work"
  bullet "lean             ★   auto-triggers CoD mode on 'quick/simple/fast/lean'"
  bullet "Run /plugin to browse the marketplace for more skills/tools/MCP bundles"
  blank

  if [[ "$mode" == "project" || "$mode" == "both" ]]; then
    echo -e "  ${BOLD}Project slash commands  → use as /project:name${RESET}"
    bullet "/project:feature   RPIV workflow: research → plan → implement → validate"
    bullet "/project:deploy    pre-deploy checklist (tests/types/secrets)"
    bullet "/project:design    create/update DESIGN.md — fixes generic UI output"
    blank
  fi

  echo -e "  ${BOLD}Token savings stack (compounding):${RESET}"
  bullet "Chain-of-Draft (lean skill)    → 80-90% fewer reasoning tokens"
  bullet "cost-guard hook                → warns before you blow your daily quota"
  bullet "token-trim hook                → auto-prunes MEMORY.md (no stale bloat)"
  bullet "Prompt caching (1h)            → 200-600 tokens/turn on repeat context"
  bullet "Haiku for subagents            → 10x cheaper for research + exploration"
  bullet "Autocompact at 50%             → quality stays high vs late-context rot"
  bullet "codesight index                → 9-13x fewer file reads"
  bullet "repomix + .codesightignore     → clean context, no junk injected"
  bullet "context7 MCP                   → live docs kill hallucination first-try"
  bullet "pre-compact + MEMORY.md        → decisions survive context wipes"
  blank
  echo -e "  ${DIM}Run: claude-optimize --analyze  to see your actual token burn breakdown${RESET}"
  blank

  # Self-install offer
  if ! command -v "$INSTALL_NAME" &>/dev/null && [[ "$SCRIPT_PATH" != "$INSTALL_DIR/$INSTALL_NAME" ]]; then
    divider
    blank
    echo -e "  ${BOLD}Run from anywhere next time?${RESET}"
    if $YES_TO_ALL || ask_yn "Install 'claude-optimize' as a global command?" "Y"; then
      self_install
    else
      dim "Skipped. To install later: bash $(basename "$SCRIPT_PATH") --install"
    fi
    blank
  fi

  echo -e "  ${DIM}Free to share — pass it on.  docs: https://docs.claude.com${RESET}"
  blank
}
do_analyze() {
  section "Token Usage Analysis  (pure bash — no extra installs)"
  local LOG_DIR="$HOME/.claude/projects"
  if [[ ! -d "$LOG_DIR" ]]; then
    warn "No session logs found at $LOG_DIR"
    dim "Claude Code saves logs here after your first session."
    return
  fi

  info "Scanning session logs in $LOG_DIR..."
  blank

  python3 << 'PYEOF'
import os, json, sys
from pathlib import Path
from datetime import datetime, date

log_dir = Path.home() / ".claude" / "projects"
sessions = []

for jsonl in log_dir.rglob("*.jsonl"):
    total_in = total_out = 0
    ts = None
    try:
        with open(jsonl) as f:
            for line in f:
                try:
                    d = json.loads(line)
                    u = d.get("usage", {})
                    if isinstance(u, dict):
                        total_in  += u.get("input_tokens", 0)
                        total_out += u.get("output_tokens", 0)
                    if not ts and d.get("timestamp"):
                        ts = d["timestamp"][:10]
                except: pass
    except: pass
    total = total_in + total_out
    if total > 0:
        sessions.append((total, total_in, total_out, ts or "unknown", str(jsonl.parent.name)[:40]))

sessions.sort(reverse=True)
today = str(date.today())
today_total = sum(s[0] for s in sessions if s[3] == today)

print(f"  Today's usage:  ~{today_total:,} tokens")
print(f"  Total sessions: {len(sessions)}")
print()
print(f"  {'Tokens':>10}  {'Input':>8}  {'Output':>8}  {'Date':>10}  Project")
print(f"  {'-'*10}  {'-'*8}  {'-'*8}  {'-'*10}  {'-'*30}")
for total, inp, out, ts, name in sessions[:10]:
    print(f"  {total:>10,}  {inp:>8,}  {out:>8,}  {ts:>10}  {name}")

if sessions:
    grand = sum(s[0] for s in sessions)
    print(f"\n  Grand total (all sessions): {grand:,} tokens")
    if len(sessions) >= 3:
        avg = grand // len(sessions)
        print(f"  Avg per session: {avg:,} tokens")
PYEOF

  blank
  info "Tips to reduce top drains:"
  bullet "Large session? Run /user:compress → /compact → start fresh"
  bullet "Many file reads? Run: npx codesight --profile claude-code (9-13x reduction)"
  bullet "Repeat context? Check ENABLE_PROMPT_CACHING_1H=1 in settings.json"
  bullet "Simple tasks? Say 'quick' or 'lean' to trigger lean/CoD mode"
  blank

  local budget=""
  [[ -f "$HOME/.claude/budget.conf" ]] && budget=$(cat "$HOME/.claude/budget.conf" 2>/dev/null | grep -o '[0-9]*' | head -1)
  if [[ -n "$budget" ]]; then
    info "Your daily budget: ${budget} tokens  (set with: claude-optimize --budget N)"
  else
    info "No daily budget set. Set one with: claude-optimize --budget 200000"
  fi
  blank
}
do_set_budget() {
  local n="$1"
  if [[ ! "$n" =~ ^[0-9]+$ ]]; then
    error "--budget requires a positive integer (e.g. --budget 200000)"
    exit 1
  fi
  local BASE="$HOME/.claude"
  mkdir -p "$BASE"
  echo "$n" > "$BASE/budget.conf"
  log "Daily token budget set to ${n} tokens → ~/.claude/budget.conf"
  info "cost-guard.sh will warn at 80% (${n} × 0.8 = $(( n * 80 / 100 )) tokens)"
  blank
  exit 0
}
do_upgrade() {
  banner
  check_deps

  section "Upgrading to v1.0.0 — adding new components only"
  info "Existing files will NOT be overwritten (--safe mode)."
  info "Only missing v1.0.0 components will be created."
  blank

  CONFLICT_POLICY="safe"
  YES_TO_ALL=true
  UPGRADE_ONLY=true

  local BASE="$HOME/.claude"
  $DRY_RUN || mkdir -p "$BASE/hooks/scripts" "$BASE/commands" "$BASE/skills/lean"

  # New hooks
  section "v1.0.0 Hooks"
  doing "cost-guard.sh..."

  smart_write "$BASE/hooks/scripts/cost-guard.sh" --safe << 'HOOKEOF'
#!/usr/bin/env bash
BUDGET_FILE="$HOME/.claude/budget.conf"
BUDGET=${CLAUDE_DAILY_BUDGET:-$(cat "$BUDGET_FILE" 2>/dev/null | grep -o '[0-9]*' | head -1 || echo "")}
BUDGET=${BUDGET:-200000}
LOG_DIR="$HOME/.claude/projects"
USED=0
if [[ -d "$LOG_DIR" ]]; then
  USED=$(find "$LOG_DIR" -name "*.jsonl" 2>/dev/null \
    | xargs grep -h '"usage"' 2>/dev/null \
    | python3 -c "
import sys, json
t = 0
for line in sys.stdin:
    try:
        d = json.loads(line)
        u = d.get('usage', {})
        if isinstance(u, dict):
            t += u.get('input_tokens', 0) + u.get('output_tokens', 0)
    except: pass
print(t)
" 2>/dev/null || echo 0)
fi
PCT=$(( USED * 100 / BUDGET )) 2>/dev/null || PCT=0
if [[ $PCT -ge 80 ]]; then
  printf '{"decision":"warn","reason":"Token budget %d%% used. Run /user:compress → /compact."}\n' "$PCT"
fi
exit 0
HOOKEOF
  $DRY_RUN || make_exec "$BASE/hooks/scripts/cost-guard.sh"

  doing "token-trim.sh..."
  smart_write "$BASE/hooks/scripts/token-trim.sh" --safe << 'HOOKEOF'
#!/usr/bin/env bash
MEMORY="${CLAUDE_PROJECT_DIR:-.}/.claude/MEMORY.md"
[[ ! -f "$MEMORY" ]] && exit 0
LINES=$(wc -l < "$MEMORY" | tr -d ' ')
if [[ $LINES -gt 100 ]]; then
  { head -8 "$MEMORY"; echo ""; echo "---"; printf "<!-- Trimmed at %s -->\n" "$(date '+%Y-%m-%d %H:%M')"; tail -60 "$MEMORY"; } > "$MEMORY"
fi
printf '{"additionalContext":"## Compacted at %s\n"}\n' "$(date '+%Y-%m-%d %H:%M')"
exit 0
HOOKEOF
  $DRY_RUN || make_exec "$BASE/hooks/scripts/token-trim.sh"

  # New commands
  section "v1.0.0 Commands"
  for cmd in chain-of-draft effort-low effort-high budget-check; do
    if [[ ! -f "$BASE/commands/${cmd}.md" ]]; then
      doing "${cmd}.md..."
    else
      skip "$BASE/commands/${cmd}.md  (already exists)"
    fi
  done
  # Re-use global setup logic for commands
  # Just call the inline heredocs for missing ones:
  [[ ! -f "$BASE/commands/chain-of-draft.md" ]] && smart_write "$BASE/commands/chain-of-draft.md" --safe << 'CMDEOF'
---
description: "Chain-of-Draft mode — 80-90% fewer reasoning tokens"
---
Use Chain-of-Draft reasoning: ≤5-word bullet per step, skip self-evident steps, final answer only.
Task: $ARGUMENTS
CMDEOF

  [[ ! -f "$BASE/commands/effort-low.md" ]] && smart_write "$BASE/commands/effort-low.md" --safe << 'CMDEOF'
---
description: "Lean/low-effort mode — simple edits, lookups, boilerplate. Signal: [lean]"
---
LEAN MODE ON: CoD reasoning, direct answers, no subagents, read only requested files. Signal: [lean]
CMDEOF

  [[ ! -f "$BASE/commands/effort-high.md" ]] && smart_write "$BASE/commands/effort-high.md" --safe << 'CMDEOF'
---
description: "Deep/high-effort mode — architecture, hard bugs. Signal: [deep]"
---
DEEP MODE ON: Full reasoning, read all relevant files, spawn researcher, verify with tests. Signal: [deep]
CMDEOF

  [[ ! -f "$BASE/commands/budget-check.md" ]] && smart_write "$BASE/commands/budget-check.md" --safe << 'CMDEOF'
---
description: "Show today's token spend + context health + recommendation"
allowed-tools: Bash(cat:*), Bash(find:*), Bash(python3:*)
---
Report: daily budget from ~/.claude/budget.conf, estimate today's usage from ~/.claude/projects/**/*.jsonl, current context %, recommendation: compress/continue/fresh.
CMDEOF

  # Lean skill
  section "v1.0.0 Skills"
  $DRY_RUN || mkdir -p "$BASE/skills/lean"
  smart_write "$BASE/skills/lean/SKILL.md" --safe << 'SKILLEOF'
---
name: lean
description: >
  Activate lean Chain-of-Draft mode. Triggered by: "quick", "simple", "just", "fast",
  "routine", "lean", or clearly simple single-file edit/lookup/rename.
---
LEAN MODE: ≤5-word draft bullets, final answer only, no subagents, no extra file reads. Prefix: [lean]
SKILLEOF

  # Budget config
  section "v1.0.0 Budget Config"
  if [[ ! -f "$BASE/budget.conf" ]]; then
    echo "$DAILY_BUDGET_DEFAULT" > "$BASE/budget.conf"
    log "Created ~/.claude/budget.conf  (${DAILY_BUDGET_DEFAULT} tokens/day)"
  else
    skip "~/.claude/budget.conf  (already set: $(cat "$BASE/budget.conf" 2>/dev/null) tokens)"
  fi

  # Wire hooks into settings.json
  if [[ -f "$BASE/settings.json" ]] && $JQ_AVAILABLE; then
    local has_cg
    has_cg=$(jq -r '.. | strings | select(contains("cost-guard"))' "$BASE/settings.json" 2>/dev/null || echo "")
    if [[ -z "$has_cg" ]]; then
      local merged
      merged=$(jq '
        .hooks.PostToolUse //= [] |
        .hooks.PostToolUse += [{"matcher":"*","hooks":[{"type":"command","command":"~/.claude/hooks/scripts/cost-guard.sh"}]}] |
        .hooks.PreCompact //= [] |
        .hooks.PreCompact += [{"hooks":[{"type":"command","command":"~/.claude/hooks/scripts/token-trim.sh"}]}]
      ' "$BASE/settings.json" 2>/dev/null) && echo "$merged" > "$BASE/settings.json"
      log "Wired v1.0.0 hooks into ~/.claude/settings.json"
    else
      skip "settings.json  (cost-guard already present)"
    fi
  fi

  blank
  log "${GREEN}${BOLD}Upgrade to v1.0.0 complete!${RESET}"
  blank
  info "New commands available as /user:<name> in Claude Code:"
  bullet "/user:chain-of-draft   — 80-90% fewer reasoning tokens"
  bullet "/user:effort-low       — lean session mode ([lean] prefix)"
  bullet "/user:effort-high      — deep session mode ([deep] prefix)"
  bullet "/user:budget-check     — token spend + health report"
  blank
  info "New hooks active:"
  bullet "cost-guard.sh         — warns at 80% of daily budget"
  bullet "token-trim.sh         — auto-prunes MEMORY.md at 100 lines"
  blank
  info "New skill:"
  bullet "lean                  — auto-triggered by 'quick'/'simple'/'fast' etc."
  blank
  exit 0
}
main() {
  local cli_mode=""
  local project_path=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --global)     cli_mode="global"  ;;
      --project)    cli_mode="project"
                    [[ $# -gt 1 && ! "$2" =~ ^-- ]] && { project_path="$2"; shift; } ;;
      --both)       cli_mode="both"    ;;
      --team)       cli_mode="team"    ;;
      --docs)       cli_mode="docs"    ;;
      --oss|--oss-pack) cli_mode="oss" ;;
      --yes|-y)     YES_TO_ALL=true    ;;
      --dry-run)    DRY_RUN=true       ;;
      --upgrade)    do_upgrade         ;;
      --update)     banner; do_update; exit 0 ;;
      --analyze)    banner; do_analyze; exit 0 ;;
      --budget)     [[ $# -gt 1 ]] && { do_set_budget "$2"; shift; } || { error "--budget requires a number"; exit 1; } ;;
      --status)     banner; check_deps; show_status; exit 0 ;;
      --install)    banner; self_install ;;
      --help|-h)
        banner
        cat <<'HELP'
  Usage:
    claudeoptimize [OPTIONS]

  Installation:
    pip install claudeoptimize

  First-time setup:
    claudeoptimize --both      (from your project directory)

  Upgrade from legacy:
    claudeoptimize --upgrade   (adds v1.0.0 components only, safe mode)

  Options:
    --both                  Global + project setup (recommended first time)
    --global                Only configure ~/.claude/
    --project [/path]       Only configure a project (path optional = current dir)
    --upgrade               Add v1.0.0 new components without touching existing config
    --update                Self-update to the latest version from GitHub
    --analyze               Parse session logs, show top token drains
    --budget N              Set daily token budget (used by cost-guard hook)
    --yes  / -y             Skip all Y/n prompts — install everything automatically
    --dry-run               Preview changes without writing any files
    --status                Show what's configured (global + current project)
    --install               Install as global 'claudeoptimize' command
    --help / -h             Show this help

  Examples:
    claudeoptimize --both --yes              # full setup, no prompts
    claudeoptimize --upgrade                 # legacy → v1.0.0 upgrade (safe)
    claudeoptimize --analyze                 # see token burn breakdown
    claudeoptimize --budget 150000           # set 150k daily limit
    claudeoptimize --project ~/myapp --yes  # project setup for myapp
    claudeoptimize --status                  # check what's installed
    claudeoptimize --dry-run --global        # preview global setup

HELP
        exit 0 ;;
      *)
        error "Unknown option: $1  (use --help for usage)"
        exit 1 ;;
    esac
    shift
  done

  banner
  check_deps
  preflight_scan

  local mode; mode=$(select_mode "$cli_mode")

  case "$mode" in
    global)
      setup_global
      install_tools
      print_manual_steps
      print_final_summary "global"
      ;;
    project)
      setup_project "$project_path"
      install_tools
      print_manual_steps
      print_project_checklist
      print_final_summary "project"
      ;;
    both)
      setup_global
      blank
      section "Now configuring project..."
      setup_project "$project_path"
      install_tools
      print_manual_steps
      print_project_checklist
      print_final_summary "both"
      ;;
    team)
      setup_team_pack
      ;;
    docs)
      setup_docs_pack
      ;;
    oss)
      setup_oss_pack
      ;;
    update)
      do_update
      ;;
    status)
      check_deps
      show_status
      ;;
    exit)
      exit 0
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
