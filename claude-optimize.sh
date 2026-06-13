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
#   v3.1  - FIX: select_mode menu swallowed by command substitution → stderr fix
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
INSTALL_NAME="claude-optimize"

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
log()    { echo -e "${GREEN}  ✔${RESET}  $*"; }
info()   { echo -e "${BLUE}  ℹ${RESET}  $*"; }
warn()   { echo -e "${YELLOW}  ⚠${RESET}  $*"; }
error()  { echo -e "${RED}  ✖${RESET}  $*" >&2; }
skip()   { echo -e "${DIM}  ↷${RESET}${DIM}  $*${RESET}"; }
bullet() { echo -e "     ${CYAN}•${RESET}  $*"; }
dim()    { echo -e "  ${DIM}$*${RESET}"; }
blank()  { echo ""; }
doing()  { echo -e "${DIM}  →${RESET}  $*${RESET}"; }  # "in progress" message
dry_run_note() { echo -e "  ${MAGENTA}[DRY-RUN]${RESET}  Would generate: ${BOLD}$*${RESET}"; }  # used by install_tools

divider() { echo -e "${DIM}  ────────────────────────────────────────────────${RESET}"; }

section() {
  blank
  echo -e "${BOLD}${CYAN}── $* ──${RESET}"
  blank
}

# ─── Step banner — the heart of the new UX ───────────────────────────────────
# Usage: step_banner <current> <total> <name> <description>
step_banner() {
  local cur="$1" tot="$2" name="$3" desc="$4"
  blank
  echo -e "${BOLD}${CYAN}  ┌─────────────────────────────────────────────────────────┐${RESET}"
  printf "${BOLD}${CYAN}  │${RESET}  ${BOLD}%-53s${CYAN}│${RESET}\n" "Step $cur/$tot · $name"
  printf "${BOLD}${CYAN}  │${RESET}  ${DIM}%-53s${RESET}${CYAN}${BOLD}│${RESET}\n" "$desc"
  echo -e "${BOLD}${CYAN}  └─────────────────────────────────────────────────────────┘${RESET}"
  blank
}

# ─── Component gate ───────────────────────────────────────────────────────────
# Returns 0 (true) = install it,  1 (false) = skip it
want_component() {
  local name="$1" desc="${2:-}"
  if $YES_TO_ALL; then
    log "${BOLD}$name${RESET}  ${DIM}(auto-yes)${RESET}"
    ((COMPONENTS_INSTALLED++)) || true
    return 0
  fi
  blank
  echo -e "  ${BOLD}${WHITE}Install: $name${RESET}"
  [[ -n "$desc" ]] && dim "$desc"
  blank
  local answer
  # VERY explicit prompt — the previous silent wait was the main UX bug
  printf "  ${CYAN}▶${RESET} ${BOLD}Install this? [Y/n]:${RESET} "
  read -r answer
  answer="${answer:-Y}"
  if [[ "${answer^^}" == "Y" ]]; then
    ((COMPONENTS_INSTALLED++)) || true
    return 0
  else
    skip "$name — skipped by user"
    ((COMPONENTS_SKIPPED++)) || true
    return 1
  fi
}

# ─── ask_yn (generic yes/no, not component-level) ─────────────────────────────
ask_yn() {
  local prompt="$1" default="${2:-Y}"
  local label
  [[ "${default^^}" == "Y" ]] && label="[Y/n]" || label="[y/N]"
  if $YES_TO_ALL; then
    echo -e "  ${DIM}(auto-yes: $prompt)${RESET}"
    return 0
  fi
  local answer
  printf "  ${CYAN}▶${RESET} $prompt $label: "
  read -r answer
  answer="${answer:-$default}"
  [[ "${answer^^}" == "Y" ]]
}

# ─── File writing engine ──────────────────────────────────────────────────────
smart_write() {
  local dest="$1"; shift
  local mode_flag="${1:-}"
  local content
  content=$(cat)

  local short_dest="${dest/#$HOME/~}"

  if $DRY_RUN; then
    echo -e "  ${MAGENTA}[DRY-RUN]${RESET}  Would write: ${BOLD}$short_dest${RESET}"
    TRACK_CREATED+=("$short_dest  [dry-run]")
    return 0
  fi

  mkdir -p "$(dirname "$dest")"

  # ── New file ──────────────────────────────────────────────────────────────
  if [[ ! -e "$dest" ]]; then
    echo "$content" > "$dest"
    local sz
    sz=$(wc -c < "$dest" | tr -d ' ')
    log "Created  ${BOLD}$short_dest${RESET}  ${DIM}(${sz}b)${RESET}"
    TRACK_CREATED+=("$short_dest")
    return 0
  fi

  # ── File exists, content identical ────────────────────────────────────────
  if [[ "$(cat "$dest")" == "$content" ]]; then
    skip "$short_dest  (identical — nothing to do)"
    TRACK_SKIPPED+=("$short_dest  [identical]")
    return 0
  fi

  # ── Forced flags ──────────────────────────────────────────────────────────
  case "$mode_flag" in
    --force)      _do_backup_write "$dest" "$content" "$short_dest"; return 0 ;;
    --safe)       skip "$short_dest  (kept your version)"; TRACK_SKIPPED+=("$short_dest  [kept]"); return 0 ;;
    --merge-json) _do_merge_json   "$dest" "$content" "$short_dest"; return 0 ;;
    --merge-md)   _do_merge_md     "$dest" "$content" "$short_dest"; return 0 ;;
  esac

  # ── No flag — follow CONFLICT_POLICY ─────────────────────────────────────
  case "$CONFLICT_POLICY" in
    safe)   skip "$short_dest  (kept your version)"; TRACK_SKIPPED+=("$short_dest  [kept]") ;;
    force)  _do_backup_write "$dest" "$content" "$short_dest" ;;
    ask|*)  _ask_conflict "$dest" "$content" "$short_dest" ;;
  esac
}

_do_backup_write() {
  local dest="$1" content="$2" short="$3"
  local bak="${dest}.bak.$(date +%Y%m%d-%H%M%S)"
  cp "$dest" "$bak"
  echo "$content" > "$dest"
  local sz; sz=$(wc -c < "$dest" | tr -d ' ')
  warn "Backed up  ${DIM}$(basename "$bak")${RESET}"
  log  "Updated   ${BOLD}$short${RESET}  ${DIM}(${sz}b)${RESET}"
  TRACK_MODIFIED+=("$short")
  TRACK_BACKUPS+=("$(basename "$bak") → $bak")
}

_do_merge_json() {
  local dest="$1" content="$2" short="$3"
  if ! $JQ_AVAILABLE; then
    warn "jq not found — cannot merge $short"
    info "Keeping your version. Merge manually if needed."
    TRACK_SKIPPED+=("$short  [jq missing — kept]")
    return
  fi
  local merged
  merged=$(jq -s '
    def merge_perms(a; b):
      { allow: ([a.allow//[], b.allow//[]] | flatten | unique),
        deny:  ([a.deny//[],  b.deny//[]]  | flatten | unique) };
    .[0] as $old | .[1] as $new |
    $new + $old +
    (if ($old.permissions and $new.permissions)
     then { permissions: merge_perms($old.permissions; $new.permissions) }
     else {} end) +
    (if ($old.mcpServers and $new.mcpServers)
     then { mcpServers: ($new.mcpServers + $old.mcpServers) }
     else {} end)
  ' "$dest" <(echo "$content") 2>/dev/null) || {
    warn "JSON merge failed for $short — keeping your version."
    TRACK_SKIPPED+=("$short  [merge failed — kept]")
    return
  }
  local bak="${dest}.bak.$(date +%Y%m%d-%H%M%S)"
  cp "$dest" "$bak"
  echo "$merged" > "$dest"
  warn "Backed up  ${DIM}$(basename "$bak")${RESET}"
  log  "Merged    ${BOLD}$short${RESET}  ${DIM}(your settings preserved, new keys added)${RESET}"
  TRACK_MODIFIED+=("$short  [merged]")
  TRACK_BACKUPS+=("$(basename "$bak") → $bak")
}

_do_merge_md() {
  local dest="$1" content="$2" short="$3"
  local added=0
  local in_block=false block_name="" block_lines=()

  while IFS= read -r line; do
    if [[ "$line" =~ ^##\  ]]; then
      if [[ -n "$block_name" && $added -eq 0 || -n "$block_name" ]]; then
        if ! grep -qF "$block_name" "$dest" 2>/dev/null; then
          { echo ""; echo "---"; echo "<!-- Added by claude-optimize -->"; echo "$block_name"; printf '%s\n' "${block_lines[@]}"; } >> "$dest"
          ((added++)) || true
        fi
      fi
      block_name="$line"; block_lines=()
    elif [[ -n "$block_name" ]]; then
      block_lines+=("$line")
    fi
  done <<< "$content"

  # flush last block
  if [[ -n "$block_name" ]] && ! grep -qF "$block_name" "$dest" 2>/dev/null; then
    { echo ""; echo "---"; echo "$block_name"; printf '%s\n' "${block_lines[@]}"; } >> "$dest"
    ((added++)) || true
  fi

  if [[ $added -gt 0 ]]; then
    log "Merged  ${BOLD}$short${RESET}  ${DIM}($added new section(s) added)${RESET}"
    TRACK_MODIFIED+=("$short  [+${added} sections]")
  else
    skip "$short  (all sections already present)"
    TRACK_SKIPPED+=("$short  [all sections present]")
  fi
}

_ask_conflict() {
  local dest="$1" content="$2" short="$3"
  blank
  warn "File exists with different content: ${BOLD}$short${RESET}"
  dim  "Existing: $(wc -c < "$dest" | tr -d ' ')b  |  New template: ${#content}b"
  blank
  echo -e "  ${CYAN}[K]${RESET}  Keep yours    — skip, keep your current file"
  echo -e "  ${CYAN}[O]${RESET}  Overwrite     — backup yours → .bak.TIMESTAMP, write new"
  echo -e "  ${CYAN}[D]${RESET}  Show diff     — see what's different, then choose again"
  [[ "$dest" == *.json ]] && echo -e "  ${CYAN}[M]${RESET}  Merge JSON    — combine both (your keys + new keys)"
  [[ "$dest" == *.md   ]] && echo -e "  ${CYAN}[M]${RESET}  Merge MD      — append only missing ## sections"
  blank
  local choice
  printf "  ${CYAN}▶${RESET} ${BOLD}Choose [K/o/d/m]:${RESET} "
  read -r choice
  choice="${choice:-K}"

  case "${choice^^}" in
    K)  skip "$short  (kept your version)"; TRACK_SKIPPED+=("$short  [kept]") ;;
    O)  _do_backup_write "$dest" "$content" "$short" ;;
    D)
      blank
      diff --color=always -u "$dest" <(echo "$content") 2>/dev/null \
        || diff -u "$dest" <(echo "$content") 2>/dev/null \
        || echo "(diff unavailable)"
      blank
      _ask_conflict "$dest" "$content" "$short"   # recursive — ask again after diff
      ;;
    M)
      if   [[ "$dest" == *.json ]]; then _do_merge_json "$dest" "$content" "$short"
      elif [[ "$dest" == *.md   ]]; then _do_merge_md   "$dest" "$content" "$short"
      else warn "Merge not supported for this file type."; TRACK_SKIPPED+=("$short  [kept]"); fi
      ;;
    *)  warn "Invalid input '$choice'. Keeping your version."; TRACK_SKIPPED+=("$short  [kept]") ;;
  esac
}

make_exec() {
  $DRY_RUN && return
  chmod +x "$1"
  local short="${1/#$HOME/~}"
  dim "chmod +x $short"
}

# ─── Dependency check ─────────────────────────────────────────────────────────
check_deps() {
  section "Dependency Check"
  local missing_required=false

  _check() {
    local cmd="$1" required="${2:-required}" hint="${3:-}"
    if command -v "$cmd" &>/dev/null; then
      local ver
      ver=$(command "$cmd" --version 2>/dev/null | head -1 | tr -d '\n' | cut -c1-40 || echo "found")
      log "${BOLD}$cmd${RESET}  ${DIM}($ver)${RESET}"
      return 0
    else
      if [[ "$required" == "required" ]]; then
        error "${BOLD}$cmd${RESET} — not found (REQUIRED)"
        [[ -n "$hint" ]] && dim "Install: $hint"
        missing_required=true
      else
        warn "${BOLD}$cmd${RESET} — not found (optional, some features disabled)"
        [[ -n "$hint" ]] && dim "Install: $hint"
      fi
      return 1
    fi
  }

  # Required
  _check node     required "https://nodejs.org (v18+)"
  _check npm      required "comes with Node.js"
  _check npx      required "npm install -g npm@latest"
  _check git      required "sudo apt install git  OR  brew install git"

  # Node version check
  if command -v node &>/dev/null; then
    local nver; nver=$(node --version 2>/dev/null | sed 's/v//' | cut -d. -f1)
    if [[ "$nver" -lt 18 ]] 2>/dev/null; then
      error "Node.js $nver detected — Claude Code needs Node 18+."
      dim  "Update: nvm install --lts  OR  https://nodejs.org"
      missing_required=true
    fi
  fi

  # Optional — jq
  if _check jq optional "sudo apt install jq  OR  brew install jq"; then
    JQ_AVAILABLE=true
  fi

  # Claude Code itself
  if command -v claude &>/dev/null; then
    local cver; cver=$(claude --version 2>/dev/null | head -1 || echo "unknown")
    log "${BOLD}claude-code${RESET}  ${DIM}($cver)${RESET}"
  else
    warn "${BOLD}claude-code${RESET} — not yet installed. Config files will be ready when you install it."
    dim  "Install after: npm install -g @anthropic-ai/claude-code"
  fi

  blank
  if $missing_required; then
    error "Required tools are missing. Fix them above, then re-run."
    blank
    echo -e "  ${BOLD}Ubuntu/Debian one-liner:${RESET}"
    bullet "curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - && sudo apt-get install -y nodejs git jq"
    blank
    echo -e "  ${BOLD}macOS one-liner:${RESET}"
    bullet "brew install node git jq"
    blank
    exit 1
  fi

  log "${GREEN}All required dependencies OK${RESET}"
  blank
}

# ─── Status report ────────────────────────────────────────────────────────────
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
  else
    echo -e "  ${DIM}No .claude/ in current directory.${RESET}"
    dim "Run from your project root: claude-optimize --project"
  fi
  blank
  divider
  echo -e "  ${DIM}Score: $check_ok / $check_total items configured${RESET}"
  blank
}

# ─── Self-install ──────────────────────────────────────────────────────────────
self_install() {
  section "Installing as global command"

  if [[ "$SCRIPT_PATH" == "$INSTALL_DIR/$INSTALL_NAME" ]]; then
    log "Already running as global command."
    return
  fi

  mkdir -p "$INSTALL_DIR"
  cp "$SCRIPT_PATH" "$INSTALL_DIR/$INSTALL_NAME"
  chmod +x "$INSTALL_DIR/$INSTALL_NAME"
  log "Installed → $INSTALL_DIR/$INSTALL_NAME"

  local updated=false
  for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    if [[ -f "$rc" ]] && ! grep -q "$INSTALL_DIR" "$rc" 2>/dev/null; then
      printf '\n# claude-optimize\nexport PATH="%s:$PATH"\n' "$INSTALL_DIR" >> "$rc"
      log "Added $INSTALL_DIR to PATH in $rc"
      updated=true
    fi
  done

  blank
  echo -e "  ${BOLD}${GREEN}Installed!${RESET}  Run this to activate in your current shell:"
  blank
  bullet "source ~/.bashrc    (bash)"
  bullet "source ~/.zshrc     (zsh)"
  blank
  echo -e "  Then from any directory:"
  bullet "claude-optimize --both     # full first-time setup"
  bullet "claude-optimize --status   # check what's configured"
  blank
  exit 0
}

# ─── Banner ───────────────────────────────────────────────────────────────────
banner() {
  blank
  echo -e "${BOLD}${CYAN}"
  echo "  ╔══════════════════════════════════════════════════════════════╗"
  echo "  ║       CLAUDE CODE OPTIMIZER  v${SCRIPT_VERSION}  ·  Free Stack          ║"
  echo "  ║    Max Output · Min Tokens · Chain-of-Draft · Solo Dev      ║"
  echo "  ╚══════════════════════════════════════════════════════════════╝"
  echo -e "${RESET}"
  if $YES_TO_ALL; then
    echo -e "  ${GREEN}${BOLD}--yes mode:${RESET}${GREEN} all components will install automatically.${RESET}"
  fi
  if $DRY_RUN; then
    echo -e "  ${MAGENTA}${BOLD}--dry-run:${RESET}${MAGENTA} no files will be written.${RESET}"
  fi
  blank
}

# ─── Preflight — scan for existing files ──────────────────────────────────────
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

# ─── Mode selection ────────────────────────────────────────────────────────────
# IMPORTANT: this function's result is captured by the caller via
#   mode=$(select_mode "$cli_mode")
# That means EVERYTHING this function writes to stdout becomes part of $mode —
# including, previously, the entire menu and the read prompt itself, which is
# why the menu never appeared and the prompt silently received an empty
# answer. Fix: all interactive/menu output goes to stderr (>&2), and only the
# final word ("global" / "project" / "both") is written to stdout.
select_mode() {
  local cli_mode="$1"
  [[ -n "$cli_mode" ]] && echo "$cli_mode" && return

  {
    section "What Do You Want to Set Up?"

    echo -e "  ${CYAN}${BOLD}1)  Global${RESET}  →  configure ${BOLD}~/.claude/${RESET}"
    dim    "      Applies to ALL your projects on this machine."
    dim    "      Creates: CLAUDE.md · settings.json · MCP servers · safety hooks"
    dim    "               subagents (researcher / tester / reviewer) · slash commands · skills"
    dim    "      ${GREEN}Do this ONCE per machine. Projects inherit it automatically.${RESET}"
    blank
    echo -e "  ${CYAN}${BOLD}2)  Project${RESET} →  configure ${BOLD}.claude/${RESET} in your project"
    dim    "      Applies to ONE project only."
    dim    "      Creates: CLAUDE.md · settings.json · .mcp.json"
    dim    "               session / discovery / quality hooks · domain agents · commands"
    dim    "      ${YELLOW}Requires global setup (option 1 or 3) to be done first.${RESET}"
    blank
    echo -e "  ${CYAN}${BOLD}3)  Both${RESET}    →  global, then project  ${DIM}(recommended for first-time setup)${RESET}"
    dim    "      Does option 1 + 2 in sequence."
    dim    "      Everything configured in a single run."
    blank
  } >&2

  local choice
  while true; do
    printf "  ${CYAN}▶${RESET} ${BOLD}Enter 1, 2, or 3 [default: 3]:${RESET} " >&2
    read -r choice
    choice="${choice:-3}"
    case "$choice" in
      1) echo "global";  break ;;
      2) echo "project"; break ;;
      3) echo "both";    break ;;
      *) error "Invalid choice '$choice'. Enter 1, 2, or 3." ;;
    esac
  done
  blank >&2
}

# ═══════════════════════════════════════════════════════════════════════════════
#  GLOBAL SETUP
# ═══════════════════════════════════════════════════════════════════════════════
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
    smart_write "$BASE/CLAUDE.md" --merge-md <<'EOF'
# Global Claude Rules
<!-- Applied to every project. HARD BUDGET: under 200 lines, ~150 rules.   -->
<!-- If Claude already follows a rule reliably, delete it — bloat causes   -->
<!-- earlier rules to get ignored. Project-specific context lives in       -->
<!-- /project/CLAUDE.md. Multi-agent / cross-tool (Cursor, Cline) configs   -->
<!-- belong in AGENTS.md instead, which Claude Code also reads.            -->

## Communication
- Code first, explanation after — never narrate what you're about to do
- Zero filler: no "Great question", "Certainly", "Of course", "Absolutely"
- Inline comments for non-obvious logic, not separate prose blocks
- No wrap-up lines ("Hope this helps!", "Let me know if…")
- If output hits limits, stop at a clean boundary: `// → Continue? (next: <topic>)`

## Code Standards
- Modern, idiomatic syntax — no legacy patterns unless explicitly asked
- Always include: imports, type hints/generics, error handling, input validation
- Security: no hardcoded secrets · parameterized queries · sanitize all inputs
- DRY, KISS, SOLID, least privilege, fail-fast, separation of concerns
- Prefer: composition > inheritance · immutability > mutation · explicit > implicit
- Note complexity: `// O(n log n) — consider cache if n>10k`
- Flag tech debt: `// TODO(debt): [what + why]`
- Flag deprecated: `// ⚠️ Deprecated in v[X] — use [Y] instead`

## Honesty
- Uncertain = say so: `// Not certain — verify against [library/docs]`
- Never invent method signatures, package names, or API shapes
- "I don't know" is always better than a plausible-sounding wrong answer
- If request is ambiguous → ask exactly one clarifying question, then proceed

## Architecture
- Name the pattern when using one: `// Repository Pattern`
- Layered: controller → service → repository
- Interface-first · dependency injection · 12-factor config

## Semantic Triggers (locked behavior)
- `refactor`  → restructure only, no behavior change, tests must pass
- `optimize`  → performance only, public interface unchanged
- `explain`   → prose only, code only if it meaningfully illustrates the point
- `scaffold`  → full project/module structure with placeholder files
- `review`    → critique quality, security, performance — direct, no softening
- `plan`      → numbered plan only, NO code until I confirm
- `minimal`   → smallest working implementation, no extras

## Codebase Discovery
- Check CLAUDE.md and .codesight/CONTEXT.md FIRST when in a repo
- Never cat/grep/find raw source until semantic search (codesight) has been called
- Never reference a file you have not read — ask for it first
- For open-ended "investigate X" requests, scope the search narrowly or
  delegate to the researcher subagent — don't let exploration fill this context
- Any UI/page/component request: apply the frontend-aesthetics skill
  (./DESIGN.md if present) — avoid generic fonts/gradients/layouts

## Compact Instructions
<!-- Read by Claude when auto-compacting (CLAUDE_AUTOCOMPACT_PCT_OVERRIDE). -->
When summarizing this conversation to free up context:
- Preserve all API/interface changes and the reason for each
- Keep unresolved error messages and any attempted fixes
- Keep the list of files modified so far (path → one-line reason)
- Summarize abandoned approaches in one line each — don't re-explore them
- Note any pending TODOs or explicit user instructions not yet done

## Token Economy (enforced by cost-guard + lean skill)
- Chain-of-Draft by default for internal reasoning: ≤5-word step bullets, not full CoT
- Lean tasks (rename/lookup/boilerplate): say "[lean]" to activate CoD auto-mode
- Hard tasks (arch/debug/multi-file refactor): activate /user:effort-high
- Context > 60% full → run /user:compress then /compact before new work
- Never read files you weren’t explicitly asked to read
- Never spawn subagents for tasks you can answer in one pass
- If uncertain about scope → ask ONE question, then proceed
EOF
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
    smart_write "$BASE/settings.json" $sj_mode <<'EOF'
{
  "_doc": "Global settings — applies to all projects. Project overrides in .claude/settings.json",
  "model": "claude-sonnet-4-6",
  "effortLevel": "normal",
  "CLAUDE_CODE_SUBAGENT_MODEL": "claude-haiku-4-5",
  "ENABLE_PROMPT_CACHING_1H": "1",
  "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "50",
  "env": {
    "CLAUDE_CODE_MAX_OUTPUT_TOKENS": "8096"
  },
  "permissions": {
    "allow": [
      "Bash(git:*)",
      "Bash(npx:*)",
      "Bash(npm:*)",
      "Bash(node:*)",
      "Bash(pnpm:*)",
      "Read(**)",
      "Write(src/**)",
      "Edit(src/**)"
    ],
    "deny": [
      "Bash(rm -rf:*)",
      "Bash(sudo rm:*)",
      "Bash(sudo:*)",
      "Write(.env:*)",
      "Write(.env.*:*)",
      "Write(*.pem:*)",
      "Write(*.key:*)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [{ "type": "command", "command": "~/.claude/hooks/scripts/block-secrets.sh" }]
      },
      {
        "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "~/.claude/hooks/scripts/block-dangerous-bash.sh" }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [{ "type": "command", "command": "~/.claude/hooks/scripts/format.sh" }]
      }
    ],
    "PreCompact": [
      {
        "hooks": [{ "type": "command", "command": "~/.claude/hooks/scripts/pre-compact.sh" }]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [{ "type": "command", "command": "~/.claude/hooks/scripts/subagent-capture.sh" }]
      }
    ]
  }
}
EOF
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
    smart_write "$BASE/claude_desktop_config.json" $mcp_mode <<'EOF'
{
  "_doc": "Global MCP servers — active for all projects. Project servers go in .mcp.json. Keep total active servers (global+project) at 3-6 — check with /context.",
  "mcpServers": {
    "context7": {
      "_doc": "Live, version-pinned docs for npm/PyPI/etc packages. Kills outdated-API hallucination. No auth. Highest-value server — keep this one on.",
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp"]
    },
    "github": {
      "_doc": "GitHub API — read issues, PRs, search code. Needs a free PAT (see manual steps). Use a READ-ONLY token (contents:read, issues:read) to limit prompt-injection blast radius from untrusted issue/PR content.",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": { "GITHUB_PERSONAL_ACCESS_TOKEN": "<YOUR_GITHUB_PAT>" }
    },
    "fetch": {
      "_doc": "Fetch any URL. Claude can read docs, changelogs, API specs, web pages.",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-fetch"]
    },
    "_optional_playwright": {
      "_doc": "ACTIVATE: rename to 'playwright'. Browser automation via accessibility snapshots (token-efficient — no raw screenshots). Lets Claude open the page it just built, check layout/contrast/overflow against DESIGN.md, and iterate — directly helps fix generic/broken UI output.",
      "command": "npx",
      "args": ["-y", "@playwright/mcp", "--headless"]
    },
    "_optional_figma": {
      "_doc": "ACTIVATE: rename to 'figma', add your Figma PAT. Dev Mode access to layer structure, variants, and design tokens — turns a real Figma file into the source of truth instead of Claude guessing the design.",
      "command": "npx",
      "args": ["-y", "figma-developer-mcp", "--stdio"],
      "env": { "FIGMA_API_KEY": "<YOUR_FIGMA_PAT>" }
    },
    "_optional_sequential-thinking": {
      "_doc": "ACTIVATE: rename to 'sequential-thinking'. Forces step-by-step reasoning before complex answers. Useful for hard architecture/debugging sessions; leave off for routine work to save tokens.",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"]
    },
    "_optional_memory": {
      "_doc": "ACTIVATE: rename to 'memory'. Knowledge-graph MCP — persist facts across sessions. No auth. Overlaps with MEMORY.md; pick one to avoid duplicate token cost.",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-memory"]
    },
    "_optional_time": {
      "_doc": "ACTIVATE: rename to 'time'. Current time + timezone awareness. No auth needed. Cheap, but only enable if your work actually needs it.",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-time"]
    }
  }
}
EOF
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
    smart_write "$BASE/hooks/scripts/block-secrets.sh" --safe <<'EOF'
#!/usr/bin/env bash
# PreToolUse:Write|Edit — blocks hardcoded secrets in file writes
INPUT=$(cat)
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // .tool_input.new_string // ""' 2>/dev/null || true)
PATTERNS='(sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36,}|AKIA[A-Z0-9]{16}|AIza[0-9A-Za-z_-]{35}|OPENAI_API_KEY=[^< ]{8,}|Bearer [A-Za-z0-9._-]{20,})'
if echo "$CONTENT" | grep -qE "$PATTERNS" 2>/dev/null; then
  printf '{"decision":"block","reason":"Hardcoded secret detected. Use env vars: process.env.KEY or os.environ[\"KEY\"]. Placeholder format: <YOUR_API_KEY>."}\n'
  exit 2
fi
exit 0
EOF

    doing "Writing block-dangerous-bash.sh..."
    smart_write "$BASE/hooks/scripts/block-dangerous-bash.sh" --safe <<'EOF'
#!/usr/bin/env bash
# PreToolUse:Bash — blocks destructive commands
INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || true)
DANGEROUS='(rm -rf /|sudo rm -rf|DROP TABLE|DROP DATABASE|chmod 777|dd if=|mkfs\.|fdisk)'
if echo "$CMD" | grep -qE "$DANGEROUS" 2>/dev/null; then
  printf '{"decision":"block","reason":"Dangerous command blocked. If intentional, run manually: %s"}\n' "$CMD"
  exit 2
fi
exit 0
EOF

    doing "Writing format.sh..."
    smart_write "$BASE/hooks/scripts/format.sh" --safe <<'EOF'
#!/usr/bin/env bash
# PostToolUse:Write|Edit — auto-formats the file Claude just wrote
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null || true)
[[ -z "$FILE" || ! -f "$FILE" ]] && exit 0
case "$FILE" in
  *.ts|*.tsx|*.js|*.jsx|*.json|*.css|*.md) npx --yes prettier --write "$FILE" 2>/dev/null || true ;;
  *.py) python -m black "$FILE" 2>/dev/null || python3 -m black "$FILE" 2>/dev/null || true ;;
  *.go) gofmt -w "$FILE" 2>/dev/null || true ;;
  *.rs) rustfmt "$FILE" 2>/dev/null || true ;;
esac
exit 0
EOF

    doing "Writing pre-compact.sh..."
    smart_write "$BASE/hooks/scripts/pre-compact.sh" --safe <<'EOF'
#!/usr/bin/env bash
# PreCompact — distill session state into MEMORY.md before context wipe
MEMORY_FILE="${CLAUDE_PROJECT_DIR:-.}/.claude/MEMORY.md"
TRANSCRIPT_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/transcripts"
mkdir -p "$TRANSCRIPT_DIR"
[[ -n "${CLAUDE_TRANSCRIPT:-}" ]] && echo "$CLAUDE_TRANSCRIPT" > "$TRANSCRIPT_DIR/$(date +%Y%m%d-%H%M%S).md" 2>/dev/null || true
printf '{"additionalContext":"## Context compacted at %s\nSee .claude/MEMORY.md for session history.\n"}\n' "$(date '+%Y-%m-%d %H:%M')"
exit 0
EOF

    doing "Writing subagent-capture.sh..."
    smart_write "$BASE/hooks/scripts/subagent-capture.sh" --safe <<'EOF'
#!/usr/bin/env bash
# SubagentStop — write subagent findings to MEMORY.md so they survive context close
INPUT=$(cat)
AGENT=$(echo "$INPUT"  | jq -r '.agent_name // "subagent"' 2>/dev/null || echo "subagent")
OUTPUT=$(echo "$INPUT" | jq -r '.output // ""'              2>/dev/null || true)
MEMORY="${CLAUDE_PROJECT_DIR:-.}/.claude/MEMORY.md"
[[ -n "$OUTPUT" && -f "$MEMORY" ]] && printf '\n## Subagent [%s] — %s\n%s\n' "$AGENT" "$(date '+%Y-%m-%d %H:%M')" "$OUTPUT" >> "$MEMORY"
exit 0
EOF

    doing "Writing cost-guard.sh..."
    smart_write "$BASE/hooks/scripts/cost-guard.sh" --safe <<'EOF'
#!/usr/bin/env bash
# PostToolUse — warn when daily token budget hits 80% (uses local JSONL logs)
BUDGET_FILE="$HOME/.claude/budget.conf"
BUDGET=${CLAUDE_DAILY_BUDGET:-$(cat "$BUDGET_FILE" 2>/dev/null | grep -o '[0-9]*' | head -1 || echo "")}
BUDGET=${BUDGET:-200000}
LOG_DIR="$HOME/.claude/projects"
USED=0
if [[ -d "$LOG_DIR" ]]; then
  TODAY=$(date +%Y-%m-%d)
  USED=$(find "$LOG_DIR" -name "*.jsonl" -newer /tmp/.ccg_ref_$(date +%Y%m%d) 2>/dev/null \
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
touch /tmp/.ccg_ref_$(date +%Y%m%d) 2>/dev/null || true
PCT=$(( USED * 100 / BUDGET )) 2>/dev/null || PCT=0
if [[ $PCT -ge 80 ]]; then
  printf '{"decision":"warn","reason":"⚠️  Token budget %d%% used (~%d/%d tokens today). Run /user:compress → /compact, or start a fresh session. Use /user:budget-check for details."}\n' "$PCT" "$USED" "$BUDGET"
fi
exit 0
EOF

    doing "Writing token-trim.sh..."
    smart_write "$BASE/hooks/scripts/token-trim.sh" --safe <<'EOF'
#!/usr/bin/env bash
# PreCompact — auto-trim MEMORY.md when > 100 lines to prevent stale context bloat
MEMORY="${CLAUDE_PROJECT_DIR:-.}/.claude/MEMORY.md"
[[ ! -f "$MEMORY" ]] && exit 0
LINES=$(wc -l < "$MEMORY" | tr -d ' ')
if [[ $LINES -gt 100 ]]; then
  HEADER=$(head -8 "$MEMORY")
  TAIL=$(tail -60 "$MEMORY")
  {
    echo "$HEADER"
    echo ""
    echo "---"
    printf "<!-- Auto-trimmed at %s: %d→68 lines -->\n" "$(date '+%Y-%m-%d %H:%M')" "$LINES"
    echo ""
    echo "$TAIL"
  } > "$MEMORY"
fi
printf '{"additionalContext":"## Context compacted at %s\nSee .claude/MEMORY.md for session history.\n"}\n' "$(date '+%Y-%m-%d %H:%M')"
exit 0
EOF

    if ! $DRY_RUN; then
      make_exec "$BASE/hooks/scripts/block-secrets.sh"
      make_exec "$BASE/hooks/scripts/block-dangerous-bash.sh"
      make_exec "$BASE/hooks/scripts/format.sh"
      make_exec "$BASE/hooks/scripts/pre-compact.sh"
      make_exec "$BASE/hooks/scripts/subagent-capture.sh"
      make_exec "$BASE/hooks/scripts/cost-guard.sh"
      make_exec "$BASE/hooks/scripts/token-trim.sh"
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
    smart_write "$BASE/agents/researcher.md" --safe <<'EOF'
---
name: researcher
description: >
  Read-only codebase explorer. Triggered by: "explore", "understand", "find where X is",
  "what does X do", "how is Y implemented", "where is Z called".
tools: Read, Grep, Glob, LS, Bash(find:*), Bash(cat:*), Bash(head:*)
model: claude-haiku-4-5
---

You are a read-only codebase explorer. Your ONLY job: understand and report. NEVER write, edit, or propose implementation.

Steps:
1. Check .codesight/CONTEXT.md or CLAUDE.md for the architecture map first
2. Use codesight semantic search before any raw file reads
3. Read only files directly relevant to the query

Return format (under 500 tokens):
## Files
- path/to/file.ext — [why relevant]

## Patterns
- [pattern]: [where it appears]

## Risks / Notes
- [anything the implementer must know]
EOF

    doing "Writing tester.md..."
    smart_write "$BASE/agents/tester.md" --safe <<'EOF'
---
name: tester
description: >
  Runs test suite, diagnoses failures, writes minimal fixes.
  Triggered by: "run tests", "fix failing tests", "did tests pass".
tools: Bash, Read, Edit, Write, Grep
model: claude-haiku-4-5
---

Run the test suite. Identify failures. Fix with minimal diffs.

Return:
## Test Run: [N passed] / [N total]

## Failures
### [test name]
- Root cause: [one sentence — the actual failure]
- Fix: [minimal diff only]

Rules:
- Do not change test intent without asking
- If >5 failures, stop and report — do not fix all blindly
EOF

    doing "Writing reviewer.md..."
    smart_write "$BASE/agents/reviewer.md" --safe <<'EOF'
---
name: reviewer
description: >
  Security-focused code reviewer. Triggered by: "review", "audit", "is this safe".
tools: Read, Grep, Glob, Bash(git diff:*)
model: claude-sonnet-4-6
---

Review for: Security (injection, auth bypass, secrets) · Performance (N+1, leaks) ·
Quality (SOLID, error swallowing, validation) · Correctness (edge cases, null deref)

Format:
[SEVERITY: CRITICAL|HIGH|MED|LOW] path/file.ext:LINE
Issue: [one sentence]
Fix: [minimal code change]

No praise. Direct only. If LGTM: output "LGTM — no issues found."
EOF
  fi

  # ── Step 6: Commands ───────────────────────────────────────────────────────
  step_banner 6 $GTOT "Slash Commands" "/plan /debug /commit /review /refactor /compress /context /new-project"
  dim "These become available as /user:name in Claude Code."
  dim "They inject structured prompts to enforce workflows — saving you from"
  dim "typing long instructions every time."
  blank
  if want_component "Slash Commands"; then

    doing "Writing plan.md..."
    smart_write "$BASE/commands/plan.md" --safe <<'EOF'
---
description: "Structured numbered plan — stop for approval before any code"
---
1. Check CLAUDE.md and .codesight/CONTEXT.md first
2. Identify: files to touch · tests needed · risks · open questions
3. Output numbered plan (max 15 steps, each max 2 sentences)
4. STOP. Write zero code until I reply "proceed".

Topic: $ARGUMENTS
EOF

    doing "Writing debug.md..."
    smart_write "$BASE/commands/debug.md" --safe <<'EOF'
---
description: "Root-cause diagnosis — jump straight to fix, no hand-holding"
---
Given this error or bug:
1. Root cause — one sentence on the ACTUAL failure (not the error message text)
2. Minimal fix — diff only, zero surrounding boilerplate
3. Prevention — one sentence: what pattern stops this recurring

Error/symptom: $ARGUMENTS
EOF

    doing "Writing commit.md..."
    smart_write "$BASE/commands/commit.md" --safe <<'EOF'
---
description: "Generate a Conventional Commit message from staged changes"
allowed-tools: Bash(git:*)
---
Run: git diff --staged --stat && git diff --staged

Generate a Conventional Commits message:
  <type>(<scope>): <subject>

Types: feat|fix|refactor|perf|test|docs|chore|ci|build
Subject: imperative mood, ≤72 chars, no period.
Body: what + why (not how) — only if non-obvious.
Footer: breaking changes or "Closes #N"

Output ONLY the git commit command ready to copy-paste:
git commit -m "<message>"
EOF

    doing "Writing review.md..."
    smart_write "$BASE/commands/review.md" --safe <<'EOF'
---
description: "Security + perf + quality audit via reviewer subagent"
allowed-tools: Read, Grep, Bash(git:*)
---
Run: git diff HEAD
Spawn the reviewer subagent on the full diff.
Return findings: CRITICAL → HIGH → MED → LOW
No praise. Direct and specific.
EOF

    doing "Writing refactor.md..."
    smart_write "$BASE/commands/refactor.md" --safe <<'EOF'
---
description: "Safe refactor — structure only, zero behavior change"
---
Refactor target: $ARGUMENTS

Rules:
- Restructure ONLY — no behavior change, no new features, public interface unchanged
- Tests must still pass after (run them to verify)
- Show before/after diff
- Name the pattern: // Extract Method · // Move to Service · // Strategy Pattern
- Flag risks: // ⚠️ potential behavior change — verify
EOF

    doing "Writing compress.md..."
    smart_write "$BASE/commands/compress.md" --safe <<'EOF'
---
description: "Compress context to MEMORY.md — do this before /compact"
allowed-tools: Read, Bash(git:*)
---
Context compression checkpoint:
1. Summarize what's been done this session (3-5 bullets max)
2. List open decisions or blockers (max 3)
3. List files modified and why (file → one-line reason)
4. Write to .claude/MEMORY.md under ## Session [YYYY-MM-DD HH:MM]
5. Output: "Context compressed. Safe to /compact now." then STOP.
EOF

    doing "Writing context.md..."
    smart_write "$BASE/commands/context.md" --safe <<'EOF'
---
description: "Debug context state — see what Claude has loaded"
allowed-tools: Read, Bash(cat:*)
---
Report context state:
1. Global CLAUDE.md loaded? (check ~/.claude/CLAUDE.md first 10 lines)
2. Project CLAUDE.md loaded? (check ./CLAUDE.md first 10 lines)
3. MEMORY.md exists? Show last 20 lines.
4. .codesight/CONTEXT.md exists? Show byte count.
5. Estimate context window % full from message count.

| Item                | Status         | Size   |
|---------------------|----------------|--------|
| Global CLAUDE.md    | loaded/missing | ?b     |
| Project CLAUDE.md   | loaded/missing | ?b     |
| MEMORY.md           | loaded/missing | ?b     |
| Codebase index      | loaded/missing | ?b     |
| Context window      | ~?% full       |        |
EOF

    doing "Writing new-project.md..."
    smart_write "$BASE/commands/new-project.md" --safe <<'EOF'
---
description: "Interview wizard → generate a project-bootstrap.sh for any stack"
argument-hint: "Optional: paste your project description to skip Round 1"
---
You are a Claude Code configuration specialist.

Interview the user (2-3 short rounds), then generate project-bootstrap.sh.

Round 1 (skip if $ARGUMENTS covers these):
- Project name + one-sentence description
- Language + runtime version (Node 22 / Python 3.12 / Go 1.22 / Rust / etc.)
- Type: web app / REST API / GraphQL / CLI / library / data pipeline
- Starting fresh or existing codebase?

Round 2:
- Full stack: frameworks, ORM, validation, test framework, UI library
- Database: PostgreSQL / MySQL / SQLite / MongoDB / Redis / none
- Package manager: pnpm / npm / yarn / pip / poetry / cargo / go mod
- Deployment: Railway / Vercel / Fly.io / AWS / Docker / bare-metal

Round 3:
- Top 3 non-negotiable codebase rules
- What must Claude NEVER do in this project?
- Architecture decisions already locked in?
- Dev commands: dev / test / lint / build

Then generate ONE complete project-bootstrap.sh. Include:
CLAUDE.md · .claude/settings.json · .mcp.json (if DB used) ·
.claude/agents/[domain]-specialist.md · .claude/commands/feature.md ·
.claude/hooks/scripts/ (session-start, discovery-gate, quality-gate)

Output ONLY the bash script between ```bash ``` fences, then:
---
Save as: project-bootstrap.sh  |  Run: bash project-bootstrap.sh
EOF
  fi

  # ── Step 6b: Token Economy Commands (v4.0) ─────────────────────────────────
  #   These commands give real-time control over token usage and reasoning effort.
  #   All available as /user:<name> in Claude Code.

    doing "Writing chain-of-draft.md..."
    smart_write "$BASE/commands/chain-of-draft.md" --safe <<'EOF'
---
description: "Chain-of-Draft mode — 80-90% fewer reasoning tokens for this task. Use for any reasoning task where you want efficient thinking, not verbose CoT."
---
Use Chain-of-Draft reasoning for this task:
- Think in ≤5-word bullet drafts per step (not full sentences)
- Skip self-evident steps
- Output final answer/code after the draft — no preamble
- Keep total draft to ≤10 bullets

Task: $ARGUMENTS
EOF

    doing "Writing effort-low.md..."
    smart_write "$BASE/commands/effort-low.md" --safe <<'EOF'
---
description: "Switch to lean/low-effort mode for this session. Use for simple edits, lookups, renames, boilerplate. Saves 80-90% reasoning tokens."
---
LEAN MODE ON for this session:
- Use Chain-of-Draft (≤5-word bullet per reasoning step)
- Direct answers only — no exploration unless asked
- Read only files explicitly requested
- Do not spawn subagents for tasks you can do in one pass
- If unsure: state it in ≤1 sentence and proceed with best guess

Signal lean mode with "[lean]" on your next response.
EOF

    doing "Writing effort-high.md..."
    smart_write "$BASE/commands/effort-high.md" --safe <<'EOF'
---
description: "Switch to deep/high-effort mode for this session. Use for complex architecture, hard bugs, multi-file refactors."
---
DEEP MODE ON for this session:
- Full reasoning before implementing
- Read all relevant files before writing code
- Spawn researcher subagent for codebase exploration
- Run tests to verify correctness before marking done
- Flag every assumption with // Assumes: [...]

Signal deep mode with "[deep]" on your next response.
EOF

    doing "Writing budget-check.md..."
    smart_write "$BASE/commands/budget-check.md" --safe <<'EOF'
---
description: "Show today's token spend, context health, and recommendations. Run when you want to know if you should compress or start a fresh session."
allowed-tools: Bash(cat:*), Bash(find:*), Bash(wc:*), Bash(python3:*)
---
Report token budget status:

1. Check budget config: cat ~/.claude/budget.conf (show daily limit or note "not set, default 200k")
2. Estimate today's usage from session logs:
   find ~/.claude/projects -name "*.jsonl" | head -3 (verify log location exists)
3. If ccusage is installed: run `ccusage today` and show output
4. Show current context: run /context
5. Give a clear recommendation: compress / continue / start fresh

Format:
| Metric           | Value        |
|------------------|--------------|
| Daily limit      | ? tokens     |
| Est. used today  | ? tokens     |
| % of budget      | ?%           |
| Context window   | ~?% full     |
| Recommendation   | ...          |

Rules:
- If budget < 20% remaining: strongly recommend /user:compress → /compact → fresh session
- If context > 60% full: recommend /user:compress now
- If both OK: "On track — continue"
EOF

  # ── Step 7: Skills ───────────────────────────────────────────────────────
  step_banner 7 $GTOT "Skills" "commit-pr · codebase-explainer · frontend-aesthetics — anti-AI-slop design defaults"
  dim "Skills live in ~/.claude/skills/<name>/SKILL.md and are auto-discovered."
  dim "Claude loads them on demand based on the 'description' field — unlike"
  dim "slash commands, no /name typing is required, and they can bundle scripts"
  dim "and reference files alongside the prompt."
  blank
  if want_component "Skills"; then

    doing "Writing skills/commit-pr/SKILL.md..."
    smart_write "$BASE/skills/commit-pr/SKILL.md" --safe <<'EOF'
---
name: commit-pr
description: Use when the user wants to commit staged changes or open/describe a pull request. Generates a Conventional Commit message and a PR title/description from the staged diff.
allowed-tools: Bash(git:*)
---
1. Run: git diff --staged --stat && git diff --staged
2. If nothing is staged, say so and stop.
3. Generate a Conventional Commits message:
   <type>(<scope>): <subject>
   Types: feat|fix|refactor|perf|test|docs|chore|ci|build
   Subject: imperative mood, ≤72 chars, no period.
   Body: what + why (not how) — only if non-obvious.
4. If the user asked for a PR, also output:
   - PR title (same as commit subject)
   - PR description: ## Summary (2-3 bullets) + ## Test plan
5. Output the ready-to-run command:
   git commit -m "<message>"
EOF

    doing "Writing skills/codebase-explainer/SKILL.md..."
    smart_write "$BASE/skills/codebase-explainer/SKILL.md" --safe <<'EOF'
---
name: codebase-explainer
description: Use when the user asks "how does X work", "where is X handled", or wants an architecture overview of unfamiliar code. Prefer the researcher subagent for the actual file exploration to keep this context clean.
---
1. Check .codesight/CONTEXT.md first — if present, answer from it before reading raw files.
2. For anything not covered there, delegate exploration to the researcher subagent
   rather than reading many files directly in the main context.
3. Answer with: entry point → call chain → key files (path + 1-line role) → gotchas.
4. Keep it under ~20 lines unless the user asks for more depth.
EOF

    doing "Writing skills/frontend-aesthetics/SKILL.md..."
    smart_write "$BASE/skills/frontend-aesthetics/SKILL.md" --safe <<'EOF'
---
name: frontend-aesthetics
description: Use whenever generating, redesigning, or styling any UI, webpage, landing page, dashboard, or component — even if the request doesn't mention "design". Counters the default "AI slop" look (generic fonts, purple gradients, predictable 3-card layouts).
---
Without explicit direction, Claude converges on generic, "on-distribution" output —
the look users call "AI slop": Inter/Roboto/Arial/system fonts, purple-to-blue
gradients on white, evenly-spaced pastel cards, a hero that says "Built for the
modern team." Actively counter this.

## 0. Check for a project design system first
- If ./DESIGN.md exists, treat it as the source of truth: match its fonts, colors,
  spacing, and "Do Not Use" list exactly. Don't re-derive a new aesthetic.
- If it doesn't exist and this is a real project (not a one-off snippet), propose
  creating one — see the project's `/project:design` command.

## 1. Typography — commit, don't hedge
- Never default to Inter, Roboto, Open Sans, Lato, Arial, or system-ui.
- Pick ONE distinctive pairing and state it before coding, e.g. a display serif
  + geometric sans, or a variable font used across extreme weights.
- Use weight extremes (200 vs 800, not 400 vs 600) and size jumps of 3x+
  (not 1.5x) between heading and body.

## 2. Color & theme — commit, don't spread thin
- One dominant color + one sharp accent, not an evenly-distributed pastel palette.
- Forbidden default: purple/blue gradient hero on a white or near-black background.
- Define every color as a CSS variable (`--color-*`) so it's a single edit later.

## 3. Layout & motion
- Avoid the reflexive "3 equal cards in a row" pattern unless the content
  genuinely has 3 parallel items — vary rhythm and density instead.
- Prefer asymmetric grids, layered depth, or a full-bleed element somewhere
  over a perfectly centered, evenly-padded stack.
- Subtle motion (hover states, transitions) > static flat cards.

## 4. State the plan before coding
Output a one-line "design statement" (fonts, dominant color, layout idea) BEFORE
writing markup/CSS, so the choice reads as intentional — then build to it.

## 5. Iterate within the system, not around it
When asked to "make X stand out", propose a change that stays inside the
existing fonts/colors/spacing (e.g. "use a larger type-scale step or a
full-bleed `--color-primary` bar") rather than introducing a new ad-hoc style.
EOF

    doing "Writing skills/README.md..."
    smart_write "$BASE/skills/README.md" --safe <<'EOF'
# Skills (~/.claude/skills/)

Each subdirectory is one skill: <name>/SKILL.md with YAML frontmatter
(name, description, optional allowed-tools/model) followed by instructions.

Unlike slash commands (.claude/commands/*.md, invoked as /user:name),
skills are loaded automatically when their `description` matches the
task — no explicit invocation needed. A command and a skill can coexist
for the same workflow; skills are the 2026-recommended shape going
forward because they support bundled scripts/reference files.

Project-local skills go in .claude/skills/ inside a repo and take
precedence over these global ones.

## Installed here
- commit-pr            — Conventional Commit + PR description from staged diff
- codebase-explainer   — architecture overview, delegates exploration to a subagent
- frontend-aesthetics  — fights the generic "AI slop" UI default; defers to
                          ./DESIGN.md when present (see /project:design)
- lean                 — auto-activates Chain-of-Draft + low-effort for simple tasks
EOF

    doing "Writing skills/lean/SKILL.md..."
    $DRY_RUN || mkdir -p "$BASE/skills/lean"
    smart_write "$BASE/skills/lean/SKILL.md" --safe <<'EOF'
---
name: lean
description: >
  Activate lean Chain-of-Draft mode for the current request. Auto-triggered when
  the user says "quick", "simple", "just", "fast", "routine", "lean", or the task
  is clearly a rename, lookup, boilerplate, or single-file edit. Saves 80-90%
  of reasoning tokens vs standard Chain-of-Thought.
---
LEAN MODE ACTIVATED for this request:
1. Reason in ≤5-word draft bullets — not full sentences
2. Skip self-evident steps entirely
3. Output only final answer/code — no preamble, no summary
4. Do not spawn subagents unless explicitly asked
5. Read only files you have been directly asked to read
6. If uncertain: state it in ≤1 sentence, then proceed with best guess

Prefix response with: [lean]
EOF
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

  # ── Step 9: Wire v4.0 hooks into settings.json ────────────────────────────
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

# ═══════════════════════════════════════════════════════════════════════════════
#  PROJECT SETUP
# ═══════════════════════════════════════════════════════════════════════════════
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
  local PTOT=10

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
    smart_write "CLAUDE.md" <<EOF
# ${PROJECT_NAME} — Claude Context
<!-- Keep under ~150 lines / ~40k tokens.
     Global style rules live in ~/.claude/CLAUDE.md — do NOT repeat here.
     This file = project-specific context only. -->

## Stack
<!-- ⚠️ EDIT THIS — replace with your actual stack before first use ⚠️ -->
- Runtime:   Node 22 / TypeScript 5.x
- DB:        PostgreSQL 16 + Drizzle ORM
- API:       Fastify 4, Zod validation
- Frontend:  Next.js 14, Tailwind CSS
- Auth:      <!-- Better Auth / NextAuth / Supabase Auth / JWT -->
- Infra:     <!-- Railway / Vercel / Fly.io / AWS / Docker -->
- Tests:     Vitest (unit), Playwright (E2E)

## Architecture
<!-- ⚠️ EDIT THIS — replace with your actual directory structure ⚠️ -->
\`\`\`
src/
  api/          # Routes → services → repositories
  services/     # Business logic — no DB access
  db/           # Schema + query helpers
  lib/          # Shared utilities — no business logic
  types/        # Global TypeScript types
\`\`\`

## Dev Commands
<!-- ⚠️ EDIT THIS — replace with your actual commands ⚠️ -->
- \`pnpm dev\`       dev server
- \`pnpm db:push\`   push schema (non-destructive)
- \`pnpm test\`      unit tests
- \`pnpm test:e2e\`  E2E tests
- \`pnpm lint\`      ESLint + tsc --noEmit

## Architecture Decisions (ADR)
<!-- Add entries as decisions are made — prevents Claude re-litigating them -->
<!-- Format: [YYYY-MM] Decision — Reason -->

## Rules
- All DB queries through repository layer — never in routes or services
- Errors: typed in services → caught in routes → RFC 7807 problem responses
- Tests required for all service-layer functions
- Parameterized queries only — never string interpolation near SQL

## ⛔ Never Do
- Never push directly to main — all changes via PR
- Never modify migration files after they've run
- Never use \`any\` type in TypeScript

## Frontend Aesthetics
- Any UI/page/component work: read ./DESIGN.md first (fonts, colors, spacing,
  Do Not Use list). The global frontend-aesthetics skill applies it automatically.
- No DESIGN.md yet? Run /project:design before generating any UI.

## Context Files
- .codesight/CONTEXT.md — codebase map (run: npx codesight --profile claude-code)
- .claude/MEMORY.md     — session decisions log
- DESIGN.md             — design system (fonts/colors/layout) for all UI work
EOF
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
    smart_write "$BASE/settings.json" $sj_mode <<'EOF'
{
  "_doc": "Commit this file. Personal machine overrides → settings.local.json (git-ignored).",
  "permissions": {
    "allow": [
      "Bash(pnpm:*)",
      "Bash(npx codesight:*)",
      "Bash(npx repomix:*)",
      "Bash(npx prettier:*)",
      "Write(src/**)",
      "Write(tests/**)",
      "Edit(src/**)",
      "Edit(tests/**)"
    ],
    "deny": [
      "Write(dist/**)",
      "Write(.next/**)",
      "Write(node_modules/**)"
    ]
  },
  "hooks": {
    "SessionStart": [
      {
        "hooks": [{ "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/scripts/session-start.sh" }]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Read|Grep",
        "hooks": [{ "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/scripts/discovery-gate.sh" }]
      }
    ],
    "Stop": [
      {
        "hooks": [{ "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/scripts/quality-gate.sh" }]
      }
    ],
    "PreCompact": [
      {
        "hooks": [{ "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/scripts/pre-compact.sh" }]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [{ "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/scripts/subagent-capture.sh" }]
      }
    ]
  }
}
EOF

    smart_write "$BASE/settings.local.json" --safe <<'EOF'
{
  "_doc": "Personal overrides for THIS machine only. NEVER commit this file.",
  "_model_override_example": "Uncomment to use Opus for hard problems:",
  "_model": "claude-opus-4-6"
}
EOF
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
    smart_write ".mcp.json" $mcp_mode <<'EOF'
{
  "_doc": "Project-scoped MCPs. Global servers are in ~/.claude/claude_desktop_config.json",
  "mcpServers": {
    "git": {
      "_doc": "Git MCP for this repo — read commits, diffs, branches.",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-git", "--repository", "."]
    }
  },
  "_optional_postgres": {
    "_note": "Rename to 'postgres' and fill in your connection string to enable",
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/server-postgres"],
    "env": { "POSTGRES_CONNECTION_STRING": "<YOUR_DB_URL>" }
  },
  "_optional_sqlite": {
    "_note": "Rename to 'sqlite' and fill in your DB path to enable",
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/server-sqlite", "--db-path", "<YOUR_DB_PATH>"]
  }
}
EOF
  fi

  # ── Step 4: Project hooks ──────────────────────────────────────────────────
  step_banner 4 $PTOT "Project Hooks" "session-start · discovery-gate · quality-gate · pre-compact · subagent-capture"
  dim "session-start: injects the codebase map (.codesight/CONTEXT.md) + MEMORY.md automatically."
  dim "discovery-gate: enforces running codesight before raw file reads (9-13x token saving)."
  dim "quality-gate: runs tsc/mypy/go vet before Claude marks a task complete."
  blank
  if want_component "Project Hooks"; then

    doing "Writing session-start.sh..."
    smart_write "$BASE/hooks/scripts/session-start.sh" --safe <<'EOF'
#!/usr/bin/env bash
# SessionStart — inject codebase map + session memory into new sessions
CONTEXT="${CLAUDE_PROJECT_DIR}/.codesight/CONTEXT.md"
MEMORY="${CLAUDE_PROJECT_DIR}/.claude/MEMORY.md"
OUT=""
[[ -f "$CONTEXT" ]] && OUT+="## Codebase Map\n$(cat "$CONTEXT")\n\n"
[[ -f "$MEMORY"  ]] && OUT+="## Session Memory\n$(cat "$MEMORY")\n"
if [[ -n "$OUT" ]]; then
  ESCAPED=$(printf '%s' "$OUT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null \
    || printf '%s' "$OUT" | jq -Rs . 2>/dev/null \
    || printf '"%s"' "$(echo "$OUT" | sed 's/"/\\"/g')")
  printf '{"additionalContext": %s}\n' "$ESCAPED"
fi
exit 0
EOF

    doing "Writing discovery-gate.sh..."
    smart_write "$BASE/hooks/scripts/discovery-gate.sh" --safe <<'EOF'
#!/usr/bin/env bash
# PreToolUse:Read|Grep — enforce codebase indexing before raw file reads
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || true)
if [[ "$FILE" =~ \.(ts|tsx|js|jsx|py|go|rs|java|rb|php|cs|swift|kt)$ ]]; then
  if [[ ! -f "${CLAUDE_PROJECT_DIR}/.codesight/CONTEXT.md" ]]; then
    printf '{"decision":"block","reason":"Codebase index not found. Run once from project root:\n  npx codesight --profile claude-code\n\nThis creates .codesight/CONTEXT.md and reduces token use 9-13x.\nTakes ~30 seconds. Then retry your request."}\n'
    exit 2
  fi
fi
exit 0
EOF

    doing "Writing quality-gate.sh..."
    smart_write "$BASE/hooks/scripts/quality-gate.sh" --safe <<'EOF'
#!/usr/bin/env bash
# Stop hook — type-check / lint before Claude marks a task complete
cd "${CLAUDE_PROJECT_DIR}" 2>/dev/null || exit 0

# Node / TypeScript
if [[ -f "package.json" && -f "tsconfig.json" ]]; then
  PM="npm"; command -v pnpm &>/dev/null && PM="pnpm"; [[ -f "yarn.lock" ]] && command -v yarn &>/dev/null && PM="yarn"
  OUT=$($PM exec tsc --noEmit --pretty false 2>&1 | head -25 || true)
  if [[ -n "$OUT" ]]; then
    printf '{"decision":"block","reason":"TypeScript errors must be fixed first:\n\n%s\n\nRun: %s exec tsc --noEmit"}\n' "$OUT" "$PM"; exit 2
  fi
fi

# Python
if [[ -f "pyproject.toml" || -f "setup.py" ]]; then
  if python -m mypy --version &>/dev/null 2>&1; then
    OUT=$(python -m mypy src/ --no-error-summary 2>&1 | tail -5 || true)
    echo "$OUT" | grep -q "error:" && {
      printf '{"decision":"block","reason":"Mypy errors:\n\n%s\n\nRun: python -m mypy src/"}\n' "$OUT"; exit 2
    }
  fi
fi

# Go
if [[ -f "go.mod" ]]; then
  OUT=$(go vet ./... 2>&1 | head -10 || true)
  [[ -n "$OUT" ]] && { printf '{"decision":"block","reason":"go vet errors:\n\n%s\n\nRun: go vet ./..."}\n' "$OUT"; exit 2; }
fi

exit 0
EOF

    doing "Writing pre-compact.sh (project)..."
    smart_write "$BASE/hooks/scripts/pre-compact.sh" --safe <<'EOF'
#!/usr/bin/env bash
# PreCompact — preserve key state before context wipe
TRANSCRIPT_DIR="${CLAUDE_PROJECT_DIR}/.claude/transcripts"
mkdir -p "$TRANSCRIPT_DIR"
[[ -n "${CLAUDE_TRANSCRIPT:-}" ]] && echo "$CLAUDE_TRANSCRIPT" > "$TRANSCRIPT_DIR/$(date +%Y%m%d-%H%M%S).md" 2>/dev/null || true
printf '{"additionalContext":"## Context compacted at %s\nPrior session summary in .claude/MEMORY.md\n"}\n' "$(date '+%Y-%m-%d %H:%M')"
exit 0
EOF

    doing "Writing subagent-capture.sh (project)..."
    smart_write "$BASE/hooks/scripts/subagent-capture.sh" --safe <<'EOF'
#!/usr/bin/env bash
# SubagentStop — save subagent findings to MEMORY.md
INPUT=$(cat)
AGENT=$(echo "$INPUT"  | jq -r '.agent_name // "subagent"' 2>/dev/null || echo "subagent")
OUTPUT=$(echo "$INPUT" | jq -r '.output // ""'              2>/dev/null || true)
MEMORY="${CLAUDE_PROJECT_DIR}/.claude/MEMORY.md"
[[ -n "$OUTPUT" && -f "$MEMORY" ]] && printf '\n## Subagent [%s] — %s\n%s\n' "$AGENT" "$(date '+%Y-%m-%d %H:%M')" "$OUTPUT" >> "$MEMORY"
exit 0
EOF

    doing "Writing token-report.sh..."
    smart_write "$BASE/hooks/scripts/token-report.sh" --safe <<'EOF'
#!/usr/bin/env bash
# PostCompact — log compact event to MEMORY.md so you know when context was trimmed
MEMORY="${CLAUDE_PROJECT_DIR:-.}/.claude/MEMORY.md"
[[ ! -f "$MEMORY" ]] && exit 0
printf '\n## Compact @ %s\n- Context summarized. Run /user:context to see new %% full.\n- Resume tip: re-read key files before continuing deep work.\n' \
  "$(date '+%Y-%m-%d %H:%M')" >> "$MEMORY"
exit 0
EOF

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
    smart_write "$BASE/agents/api-designer.md" --safe <<'EOF'
---
name: api-designer
description: >
  REST/OpenAPI specialist. Triggered by: "design this endpoint", "what status code",
  "OpenAPI spec", "request/response schema", "review this API".
tools: Read, Grep, Glob
model: claude-sonnet-4-6
---

REST API design rules:
- Verbs: GET=read, POST=create, PUT=replace, PATCH=partial, DELETE=remove
- Status codes: 200/201/204 success · 400 bad request · 401 unauth · 403 forbidden · 404 not found · 422 unprocessable · 500 server error
- Errors: RFC 7807 Problem Details (type, title, status, detail, instance)
- Pagination: cursor-based for large · offset+limit for small
- Versioning: URL prefix /v1/ for breaking changes
- Input: validate at boundary (Zod / Pydantic) — never trust caller
- Never expose internal errors or stack traces in responses

Return: OpenAPI 3.1 YAML snippet + example request/response.
EOF

    doing "Writing db-migrator.md..."
    smart_write "$BASE/agents/db-migrator.md" --safe <<'EOF'
---
name: db-migrator
description: >
  Schema migration specialist. Triggered by: "add migration", "schema change",
  "new column", "rename table", "add index".
tools: Read, Bash(readonly), Grep
model: claude-haiku-4-5
---

Migration rules:
- Every migration must be reversible (up + down)
- Never drop columns in same migration as data migration
- Index every new foreign key
- Backfill in a SEPARATE migration from schema change
- Transactions for multi-statement migrations
- Never string-interpolate SQL — parameterized only

Return: migration file content only. Include:
1. Up migration (with rollback plan if destructive)
2. Down migration
3. // WARNING: [any data loss risk]
EOF
  fi

  # ── Step 6: Project commands ───────────────────────────────────────────────
  step_banner 6 $PTOT "Project Commands" "/project:feature (RPIV) · /project:deploy (preflight) · /project:design (DESIGN.md)"
  dim "/project:feature enforces Research → Plan → Implement → Validate workflow."
  dim "This stops Claude from diving into code before understanding the codebase."
  blank
  if want_component "Project Commands"; then

    doing "Writing feature.md..."
    smart_write "$BASE/commands/feature.md" --safe <<'EOF'
---
description: "Full feature workflow: Research → Plan → Implement → Validate"
argument-hint: "Feature description"
---
Phase 1 — RESEARCH (spawn researcher subagent):
Explore relevant code. Return: files to touch, patterns, risks.
Do NOT start implementing.

Phase 2 — PLAN (main context):
Numbered plan, max 10 steps.
STOP. Wait for approval before Phase 3.

Phase 3 — IMPLEMENT (after approval only):
Step by step. Show diff after each step. Confirm before proceeding.

Phase 4 — VALIDATE (spawn tester subagent):
Run full test suite. Return: pass/fail + root causes.

Feature: $ARGUMENTS
EOF

    doing "Writing deploy.md..."
    smart_write "$BASE/commands/deploy.md" --safe <<'EOF'
---
description: "Pre-deploy checklist — run before any deployment"
allowed-tools: Bash(git:*), Bash(pnpm:*)
---
Pre-deploy checklist — report [PASS] or [FAIL] for each:

1. All tests pass: pnpm test
2. No TypeScript errors: pnpm tsc --noEmit
3. No lint errors: pnpm lint
4. No uncommitted changes: git status
5. On correct branch: git branch --show-current
6. .env.example up to date vs .env (check for missing keys)
7. No TODO(debt) in this diff: git diff main..HEAD | grep -c "TODO(debt)"
8. No hardcoded secrets: git diff main..HEAD | grep -E "(sk-|ghp_|AKIA)"

Block deployment if ANY FAIL.
EOF

    doing "Writing design.md (command)..."
    smart_write "$BASE/commands/design.md" --safe <<'EOF'
---
description: "Create or update DESIGN.md — the project's anti-generic design system"
argument-hint: "Optional: paste brand references / vibe words to skip the interview"
---
Goal: produce or refresh ./DESIGN.md, the single source of truth every UI
prompt in this project should be checked against (the frontend-aesthetics
skill reads it automatically).

If ./DESIGN.md exists: show its current Typography/Color/Layout sections,
ask only what needs to change, then update it (and add a Changelog line).

If it doesn't exist, run a short interview (skip anything $ARGUMENTS already
answers):
1. Vibe in 2-3 words (e.g. "brutalist editorial", "warm SaaS, confident")
2. 1-3 reference sites/brands/IDE themes for inspiration (style only, not copy)
3. One dominant color (hex or description) + one sharp accent
4. Display font + body font preference, or "you choose — just not Inter/Roboto/Arial"
5. Anything explicitly forbidden (e.g. "no purple gradients", "no rounded corners")

Then write ./DESIGN.md with sections: Typography, Color Palette (as CSS
variables), Spacing & Shape, Component Conventions, Layout Rules, Do Not Use,
Personality & Reference, Changelog. Apply the same anti-generic defaults as
the frontend-aesthetics skill (weight/size extremes, one dominant color +
accent, no Inter/Roboto/Arial/purple-gradients) for anything the interview
didn't specify. Keep it under 100 lines.
EOF
  fi

  # ── Step 7: MEMORY.md + .gitignore ────────────────────────────────────────
  step_banner 7 $PTOT "MEMORY.md + .gitignore" "Session decisions log + .gitignore entries for Claude files"
  dim "MEMORY.md is auto-updated by hooks. Use it to record key decisions,"
  dim "solved bugs, and established patterns — it survives context resets."
  blank
  if want_component "MEMORY.md + .gitignore"; then

    doing "Writing .claude/MEMORY.md..."
    smart_write "$BASE/MEMORY.md" --safe <<'EOF'
# Session Memory
<!-- Auto-updated by hooks. Manually add key decisions here. -->

## Key Decisions
<!-- [YYYY-MM-DD] Decision — Context -->

## Bugs Solved
<!-- Pattern: what looked like X was actually Y -->

## Patterns Established
<!-- "We use X approach for Y because Z" -->

## Do Not Touch
<!-- Files / patterns / code that must not change -->
EOF

    doing "Updating .gitignore..."
    if ! $DRY_RUN; then
      local BLOCK="
# Claude Code (claude-optimize)
.claude/settings.local.json
.claude/MEMORY.md
.claude/transcripts/
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
    smart_write "DESIGN.md" --safe <<'EOF'
# Design System
<!-- Read automatically by the frontend-aesthetics skill for ANY UI work in
     this project. Run /project:design for a guided interview, or edit the
     ⚠️ EDIT THIS placeholders below directly. Keep under ~100 lines. -->

## Personality & Reference
<!-- ⚠️ EDIT THIS — 2-3 vibe words + 1-3 reference sites/brands/IDE themes ⚠️ -->
- Vibe: <!-- e.g. "brutalist editorial", "warm SaaS, confident" -->
- References (style only, never copy): <!-- e.g. "Linear, Vercel docs, Monokai" -->

## Typography
<!-- ⚠️ EDIT THIS — never Inter / Roboto / Open Sans / Lato / Arial / system-ui ⚠️ -->
- Display: <!-- e.g. Fraunces -->
- Body:    <!-- e.g. Bricolage Grotesque -->
- Mono:    <!-- e.g. JetBrains Mono -->
- Weight extremes: use e.g. 200 vs 800, not 400 vs 600
- Scale jumps of 3x+ between heading and body sizes, not 1.5x

## Color Palette
<!-- ⚠️ EDIT THIS — one dominant color + one sharp accent, defined as CSS vars ⚠️ -->
```css
:root {
  --color-primary:   #__EDIT__;
  --color-accent:    #__EDIT__;
  --color-bg:        #__EDIT__;
  --color-surface:   #__EDIT__;
  --color-text:      #__EDIT__;
}
```

## Spacing & Shape
- Base unit: <!-- e.g. 8px -->
- Radius:    <!-- e.g. 4px sharp / 24px soft — pick one and use everywhere -->
- Border/shadow style: <!-- e.g. 1px hairline borders, no drop shadows -->

## Component Conventions
<!-- e.g. "Buttons: solid --color-primary, no gradients, sharp 2px radius" -->

## Layout Rules
- Avoid the reflexive "3 equal cards in a row" unless content is genuinely
  3 parallel items — vary rhythm/density, use asymmetric grids or full-bleed
  sections instead.
- Subtle motion (hover/transition) over static flat cards.

## Do Not Use
- Inter, Roboto, Open Sans, Lato, Arial, or any system-ui font stack
- Purple-to-blue gradient hero sections on white or near-black backgrounds
- Generic "Built for the modern team" / stock SaaS hero copy
<!-- ⚠️ EDIT THIS — add anything specific to this brand/project ⚠️ -->

## Changelog
- [YYYY-MM-DD] Initial design system created
EOF
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
    smart_write ".repomix.config.json" --safe <<'EOF'
{
  "_doc": "Repomix config — run: npx repomix  to pack repo for Claude. Edit ignore list as needed.",
  "output": {
    "filePath": ".repomix-output.md",
    "style": "markdown",
    "showLineNumbers": false,
    "copyToClipboard": false,
    "removeComments": false,
    "removeEmptyLines": false,
    "topFilesLength": 10,
    "showFileSummary": true
  },
  "ignore": {
    "useGitignore": true,
    "useDefaultPatterns": true,
    "customPatterns": [
      "dist/**", ".next/**", "build/**", "out/**",
      "node_modules/**", "coverage/**", ".nyc_output/**",
      "*.min.js", "*.min.css", "*.bundle.js",
      "*.lock", "*.log", "*.map",
      "*.png", "*.jpg", "*.jpeg", "*.gif", "*.svg", "*.ico", "*.webp",
      "*.woff", "*.woff2", "*.ttf", "*.eot",
      ".codesight/cache/**", ".claude/transcripts/**",
      ".repomix-output.md", "__pycache__/**", "*.pyc",
      ".venv/**", "venv/**", ".env/**"
    ]
  },
  "security": {
    "enableSecurityCheck": true
  }
}
EOF

    doing "Writing .codesightignore..."
    smart_write ".codesightignore" --safe <<'EOF'
# codesightignore — mirrors .gitignore + build artifacts
# Generated by claude-optimize v4.0
node_modules/
dist/
build/
out/
.next/
coverage/
.nyc_output/
__pycache__/
.venv/
venv/
*.min.js
*.min.css
*.bundle.js
*.map
*.lock
*.log
*.pyc
*.png
*.jpg
*.jpeg
*.gif
*.svg
*.ico
*.webp
.codesight/cache/
.claude/transcripts/
.repomix-output.md
EOF

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
      smart_write "$BASE/hooks/scripts/quality-gate.sh" --force <<EOF
#!/usr/bin/env bash
# Stop hook — type-check / lint before Claude marks a task complete
# Auto-generated by claude-optimize v4.0 — Python root: $py_src
cd "\${CLAUDE_PROJECT_DIR}" 2>/dev/null || exit 0

# ── Node / TypeScript ────────────────────────────────────────────────────────
if [[ -f "package.json" && -f "tsconfig.json" ]]; then
  PM="npm"
  command -v pnpm &>/dev/null && PM="pnpm"
  [[ -f "yarn.lock" ]] && command -v yarn &>/dev/null && PM="yarn"
  OUT=\$(\$PM exec tsc --noEmit --pretty false 2>&1 | head -25 || true)
  if [[ -n "\$OUT" ]]; then
    printf '{"decision":"block","reason":"TypeScript errors must be fixed:\\n\\n%s\\n\\nRun: %s exec tsc --noEmit"}\n' "\$OUT" "\$PM"
    exit 2
  fi
fi

# ── Python / mypy ────────────────────────────────────────────────────────────
if [[ -f "pyproject.toml" || -f "setup.py" || -f "setup.cfg" ]]; then
  PY_SRC="$py_src"
  # auto-discover: prefer src/ > app/ > package name > .
  if [[ -z "\$PY_SRC" || "\$PY_SRC" == "." ]]; then
    for d in src app lib; do
      [[ -d "\$d" ]] && PY_SRC="\$d" && break
    done
    [[ -z "\$PY_SRC" ]] && PY_SRC="."
  fi
  if python3 -m mypy --version &>/dev/null 2>&1; then
    OUT=\$(python3 -m mypy "\$PY_SRC" --no-error-summary --ignore-missing-imports 2>&1 | tail -8 || true)
    echo "\$OUT" | grep -q "error:" && {
      printf '{"decision":"block","reason":"Mypy errors in %s:\\n\\n%s\\n\\nRun: python3 -m mypy %s"}\n' "\$PY_SRC" "\$OUT" "\$PY_SRC"
      exit 2
    }
  fi
fi

# ── Go ───────────────────────────────────────────────────────────────────────
if [[ -f "go.mod" ]]; then
  OUT=\$(go vet ./... 2>&1 | head -10 || true)
  [[ -n "\$OUT" ]] && {
    printf '{"decision":"block","reason":"go vet errors:\\n\\n%s\\n\\nRun: go vet ./..."}\n' "\$OUT"
    exit 2
  }
fi

# ── Rust ─────────────────────────────────────────────────────────────────────
if [[ -f "Cargo.toml" ]]; then
  OUT=\$(cargo check --message-format short 2>&1 | grep "^error" | head -10 || true)
  [[ -n "\$OUT" ]] && {
    printf '{"decision":"block","reason":"Rust errors:\\n\\n%s\\n\\nRun: cargo check"}\n' "\$OUT"
    exit 2
  }
fi

exit 0
EOF
      make_exec "$BASE/hooks/scripts/quality-gate.sh"
    fi
  else
    info "quality-gate.sh not found — it will be created in project hooks step."
  fi

  blank
  log "${GREEN}${BOLD}Project setup complete in: $(pwd)${RESET}"
  blank
}

# ═══════════════════════════════════════════════════════════════════════════════
#  TOOL INSTALLER  (v4.0 — actually installs, not just hints)
# ═══════════════════════════════════════════════════════════════════════════════
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

  # ── Tool 4: claude-mem (plugin — must be installed INSIDE Claude Code) ───────
  step_banner "T4" "T5" "claude-mem" "Persistent memory plugin — survives session restarts via SQLite"
  dim "claude-mem stores session history, compresses it, re-injects relevant context."
  dim "Addresses 'session amnesia' — Claude remembers what it learned in past sessions."
  dim "${YELLOW}⚠️  This is a Claude Code PLUGIN — cannot be installed by this script.${RESET}"
  dim "You must install it INSIDE a Claude Code session (see manual steps below)."
  blank
  if want_component "claude-mem (show install instructions)"; then
    blank
    echo -e "  ${BOLD}Install claude-mem inside Claude Code:${RESET}"
    bullet "1. Open Claude Code: cd /your/project && claude"
    bullet "2. Run: /plugin marketplace add thedotmack/claude-mem"
    bullet "3. Run: /plugin install claude-mem"
    bullet "4. Restart Claude Code — memory is now persistent"
    blank
    dim "What it saves: re-reading old decisions, re-exploring same code paths."
    dim "Works alongside MEMORY.md (complementary, not a replacement)."
    blank

    # Write a reminder to MEMORY.md if it exists
    local mem_file="${CLAUDE_PROJECT_DIR:-.}/.claude/MEMORY.md"
    if [[ -f "$mem_file" ]] && ! $DRY_RUN; then
      if ! grep -q "claude-mem" "$mem_file" 2>/dev/null; then
        printf '\n## Tool Reminder\n- Install claude-mem plugin for persistent memory across sessions:\n  /plugin marketplace add thedotmack/claude-mem → /plugin install claude-mem\n' >> "$mem_file"
        log "Reminder added to .claude/MEMORY.md"
      fi
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

# ═══════════════════════════════════════════════════════════════════════════════
#  POST-SETUP OUTPUT
# ═══════════════════════════════════════════════════════════════════════════════

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
  bullet "Replace dev commands with your ACTUAL commands (pnpm/npm/make/cargo)"
  bullet "Delete placeholder comments when done. Target: under 150 lines."
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
  echo -e "  ${BOLD}${CYAN}★ New in v4.0 — Token Economy Commands${RESET}"
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

# ═══════════════════════════════════════════════════════════════════════════════
#  NEW v4.0 FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# ── do_analyze: parse session JSONL logs, show top token drains ───────────────
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

# ── do_set_budget: write daily token ceiling to budget.conf ──────────────────
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

# ── do_upgrade: add only v4.0 new components without full re-run ──────────────
do_upgrade() {
  banner
  check_deps

  section "Upgrading to v4.0 — adding new components only"
  info "Existing files will NOT be overwritten (--safe mode)."
  info "Only missing v4.0 components will be created."
  blank

  CONFLICT_POLICY="safe"
  YES_TO_ALL=true
  UPGRADE_ONLY=true

  local BASE="$HOME/.claude"
  $DRY_RUN || mkdir -p "$BASE/hooks/scripts" "$BASE/commands" "$BASE/skills/lean"

  # New hooks
  section "v4.0 Hooks"
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
  section "v4.0 Commands"
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
  section "v4.0 Skills"
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
  section "v4.0 Budget Config"
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
      log "Wired v4.0 hooks into ~/.claude/settings.json"
    else
      skip "settings.json  (cost-guard already present)"
    fi
  fi

  blank
  log "${GREEN}${BOLD}Upgrade to v4.0 complete!${RESET}"
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

# ═══════════════════════════════════════════════════════════════════════════════
#  MAIN
# ═══════════════════════════════════════════════════════════════════════════════
main() {
  local cli_mode=""
  local project_path=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --global)     cli_mode="global"  ;;
      --project)    cli_mode="project"
                    [[ $# -gt 1 && ! "$2" =~ ^-- ]] && { project_path="$2"; shift; } ;;
      --both)       cli_mode="both"    ;;
      --yes|-y)     YES_TO_ALL=true    ;;
      --dry-run)    DRY_RUN=true       ;;
      --upgrade)    do_upgrade         ;;
      --analyze)    banner; do_analyze; exit 0 ;;
      --budget)     [[ $# -gt 1 ]] && { do_set_budget "$2"; shift; } || { error "--budget requires a number"; exit 1; } ;;
      --status)     banner; check_deps; show_status; exit 0 ;;
      --install)    banner; self_install ;;
      --help|-h)
        banner
        cat <<'HELP'
  Usage:
    bash claude-optimize.sh [OPTIONS]

  First-time setup:
    chmod +x claude-optimize.sh && ./claude-optimize.sh --install
    source ~/.bashrc
    claude-optimize --both      (from any directory)

  Upgrade from v3.x:
    claude-optimize --upgrade   (adds v4.0 components only, safe mode)

  Options:
    --both                  Global + project setup (recommended first time)
    --global                Only configure ~/.claude/
    --project [/path]       Only configure a project (path optional = current dir)
    --upgrade               Add v4.0 new components without touching existing config
    --analyze               Parse session logs, show top token drains
    --budget N              Set daily token budget (used by cost-guard hook)
    --yes  / -y             Skip all Y/n prompts — install everything automatically
    --dry-run               Preview changes without writing any files
    --status                Show what's configured (global + current project)
    --install               Install as global 'claude-optimize' command
    --help / -h             Show this help

  Examples:
    claude-optimize --both --yes              # full setup, no prompts
    claude-optimize --upgrade                 # v3.x → v4.0 upgrade (safe)
    claude-optimize --analyze                 # see token burn breakdown
    claude-optimize --budget 150000           # set 150k daily limit
    claude-optimize --project ~/myapp --yes  # project setup for myapp
    claude-optimize --status                  # check what's installed
    claude-optimize --dry-run --global        # preview global setup

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
  esac
}

main "$@"
