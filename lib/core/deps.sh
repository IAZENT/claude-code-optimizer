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
