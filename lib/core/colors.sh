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
step_banner() {
  local cur="$1" tot="$2" name="$3" desc="$4"
  blank
  echo -e "${BOLD}${CYAN}  ┌─────────────────────────────────────────────────────────┐${RESET}"
  printf "${BOLD}${CYAN}  │${RESET}  ${BOLD}%-53s${CYAN}│${RESET}\n" "Step $cur/$tot · $name"
  printf "${BOLD}${CYAN}  │${RESET}  ${DIM}%-53s${RESET}${CYAN}${BOLD}│${RESET}\n" "$desc"
  echo -e "${BOLD}${CYAN}  └─────────────────────────────────────────────────────────┘${RESET}"
  blank
}
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
