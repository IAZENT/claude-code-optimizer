setup_oss_pack() {
  local BASE="$HOME/.claude"
  local OTOT=2
  
  section "OSS Skill Pack"
  dim "These are vetted community skills that live in your global ~/.claude/skills/"
  
  # Step 1: Interview
  step_banner 1 $OTOT "Skill Selection" "Choose which skills to install"
  local want_tester
  local want_design
  
  if ask_yn "Install 'webapp-tester' skill (Playwright e2e/UI checks)?" "Y"; then want_tester=true; else want_tester=false; fi
  if ask_yn "Install 'design-system' skill (Design token scaffolding)?" "Y"; then want_design=true; else want_design=false; fi
  
  $DRY_RUN || mkdir -p "$BASE/skills"
  
  # Step 2: Install Skills
  step_banner 2 $OTOT "Installing Skills" "Copying skills to ~/.claude/skills/"
  
  if $want_tester; then
    $DRY_RUN || mkdir -p "$BASE/skills/webapp-tester"
    write_template "templates/oss-pack/skills/webapp-tester/SKILL.md" "$BASE/skills/webapp-tester/SKILL.md" --safe
  fi
  
  if $want_design; then
    $DRY_RUN || mkdir -p "$BASE/skills/design-system"
    write_template "templates/oss-pack/skills/design-system/SKILL.md" "$BASE/skills/design-system/SKILL.md" --safe
  fi
  
  blank
  log "${GREEN}${BOLD}OSS Skill Pack setup complete.${RESET}"
}
