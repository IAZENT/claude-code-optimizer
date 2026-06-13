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

ask_menu() {
  local prompt="$1"
  shift
  local options=("$@")
  local selected=0
  local key

  # Hide cursor
  tput civis >&2
  # Cleanup on exit or Ctrl+C
  trap 'tput cnorm >&2; exit 1' SIGINT

  echo -e "  ${BOLD}$prompt${RESET}" >&2

  while true; do
    for i in "${!options[@]}"; do
      if [[ $i -eq $selected ]]; then
        echo -e "    ${CYAN}❯ ${options[$i]}${RESET}" >&2
      else
        echo -e "      ${DIM}${options[$i]}${RESET}" >&2
      fi
    done

    # Read exactly 1 char, silent
    read -rsn1 key

    case "$key" in
      $'\x1b') # Handle escape sequences (arrows)
        read -rsn2 -t 0.1 key
        if [[ "$key" == "[A" ]]; then # Up
          ((selected--))
          [[ $selected -lt 0 ]] && selected=$((${#options[@]} - 1))
        elif [[ "$key" == "[B" ]]; then # Down
          ((selected++))
          [[ $selected -ge ${#options[@]} ]] && selected=0
        fi
        ;;
      "") # Enter
        break
        ;;
    esac

    # Clear lines to redraw
    for ((i=0; i<${#options[@]}; i++)); do
      tput cuu1 >&2
      tput el >&2
    done
  done

  # Clear the menu text once selection is made
  for ((i=0; i<${#options[@]}; i++)); do
    tput cuu1 >&2
    tput el >&2
  done
  tput cuu1 >&2
  tput el >&2

  # Restore cursor
  tput cnorm >&2
  trap - SIGINT
  
  # Return the selected index (0-based)
  echo "$selected"
}

select_mode() {
  local cli_mode="$1"
  [[ -n "$cli_mode" ]] && echo "$cli_mode" && return

  local options=(
    "Global + Project Setup (Recommended)"
    "Global Setup Only"
    "Project Setup Only"
    "Team Pack Setup"
    "Docs Pack Setup"
    "OSS Skill Pack Setup"
    "Update claudeoptimize"
    "Check Optimization Status"
    "Exit"
  )

  local choice
  choice=$(ask_menu "What Do You Want to Set Up?" "${options[@]}")

  case "$choice" in
    0) echo "both" ;;
    1) echo "global" ;;
    2) echo "project" ;;
    3) echo "team" ;;
    4) echo "docs" ;;
    5) echo "oss" ;;
    6) echo "update" ;;
    7) echo "status" ;;
    8) echo "exit" ;;
    *) echo "exit" ;;
  esac
}
