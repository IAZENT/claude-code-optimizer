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

  blank
  log "${GREEN}${BOLD}Project setup complete in: $(pwd)${RESET}"
  blank
}

# ═══════════════════════════════════════════════════════════════════════════════
#  TOOL INSTALLER  (v1.0.0 — actually installs, not just hints)
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

# ═══════════════════════════════════════════════════════════════════════════════
#  NEW v1.0.0 FUNCTIONS
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

# ── do_upgrade: add only v1.0.0 new components without full re-run ──────────────
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

  Upgrade from legacy:
    claude-optimize --upgrade   (adds v1.0.0 components only, safe mode)

  Options:
    --both                  Global + project setup (recommended first time)
    --global                Only configure ~/.claude/
    --project [/path]       Only configure a project (path optional = current dir)
    --upgrade               Add v1.0.0 new components without touching existing config
    --analyze               Parse session logs, show top token drains
    --budget N              Set daily token budget (used by cost-guard hook)
    --yes  / -y             Skip all Y/n prompts — install everything automatically
    --dry-run               Preview changes without writing any files
    --status                Show what's configured (global + current project)
    --install               Install as global 'claude-optimize' command
    --help / -h             Show this help

  Examples:
    claude-optimize --both --yes              # full setup, no prompts
    claude-optimize --upgrade                 # legacy → v1.0.0 upgrade (safe)
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
