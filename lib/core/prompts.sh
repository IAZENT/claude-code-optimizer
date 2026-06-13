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
ask_yn() {
  local prompt="$1" default="${2:-Y}"
  local label
  [[ "${default^^}" == "Y" ]] && label="[Y/n]" || label="[y/N]"
  if $YES_TO_ALL; then
    echo -e "  ${DIM}(auto-yes: $prompt)${RESET}" >&2
    return 0
  fi
  local answer
  printf "  ${CYAN}▶${RESET} $prompt $label: " >&2
  read -r answer
  answer="${answer:-$default}"
  [[ "${answer^^}" == "Y" ]]
}
ask_choice() {
  local prompt="$1"
  local options=("${@:2}")
  local default="${options[0]}"
  local answer

  if $YES_TO_ALL; then
    echo -e "  ${DIM}(auto-yes: $prompt → $default)${RESET}" >&2
    echo "$default"
    return 0
  fi

  echo -e "  ${BOLD}$prompt${RESET}" >&2
  for i in "${!options[@]}"; do
    echo "    $((i+1))) ${options[$i]}" >&2
  done

  while true; do
    printf "  ${CYAN}▶${RESET} Choose [1-${#options[@]}] (default 1): " >&2
    read -r answer
    answer="${answer:-1}"
    if [[ "$answer" =~ ^[0-9]+$ ]] && ((answer >= 1 && answer <= ${#options[@]})); then
      echo "${options[$((answer-1))]}"
      return 0
    fi
    echo -e "  ${RED}Invalid choice.${RESET}" >&2
  done
}

ask_number() {
  local prompt="$1"
  local min="$2"
  local max="$3"
  local default="$4"
  local answer

  if $YES_TO_ALL; then
    echo -e "  ${DIM}(auto-yes: $prompt → $default)${RESET}" >&2
    echo "$default"
    return 0
  fi

  while true; do
    printf "  ${CYAN}▶${RESET} $prompt [$min-$max, default $default]: " >&2
    read -r answer
    answer="${answer:-$default}"
    if [[ "$answer" =~ ^[0-9]+$ ]] && ((answer >= min && answer <= max)); then
      echo "$answer"
      return 0
    fi
    echo -e "  ${RED}Please enter a number between $min and $max.${RESET}" >&2
  done
}

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
    echo -e "  ${CYAN}${BOLD}4)  Team Pack${RESET}    →  multi-agent + workflow setup"
    echo -e "  ${CYAN}${BOLD}5)  Docs Pack${RESET}    →  PRD + architecture + specs generation"
    echo -e "  ${CYAN}${BOLD}6)  OSS Skill Pack${RESET} →  install vetted open-source skills"
    blank
  } >&2

  local choice
  while true; do
    printf "  ${CYAN}▶${RESET} ${BOLD}Enter 1-6 [default: 3]:${RESET} " >&2
    read -r choice
    choice="${choice:-3}"
    case "$choice" in
      1) echo "global";  break ;;
      2) echo "project"; break ;;
      3) echo "both";    break ;;
      4) echo "team";    break ;;
      5) echo "docs";    break ;;
      6) echo "oss";     break ;;
      *) error "Invalid choice '$choice'. Enter a number between 1 and 6." ;;
    esac
  done
  blank >&2
}
