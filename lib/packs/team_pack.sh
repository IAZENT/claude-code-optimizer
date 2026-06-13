setup_team_pack() {
  local BASE=".claude"
  local TTOT=4
  
  if [[ ! -d "$BASE" ]] && ! $DRY_RUN; then
    warn "Project must be initialized first. Run: claude-optimize --project"
    return 1
  fi
  
  section "Team Collaboration Pack"
  
  # Step 1: Interview
  step_banner 1 $TTOT "Team Configuration" "Interview to set up team roles and merge strategy"
  local member_count
  local my_role
  local merge_strat
  local hosting
  
  member_count=$(ask_number "How many team members?" 2 8 3)
  my_role=$(ask_choice "What is YOUR role on this project?" "fullstack-lead" "frontend" "backend" "database" "ml-data" "devops")
  merge_strat=$(ask_choice "How do you want merges handled?" "Orchestrator" "Sequential" "Human")
  hosting=$(ask_choice "Repo hosting?" "github" "gitlab" "none-yet")
  
  # Write team.config.json
  if ! $DRY_RUN; then
    mkdir -p "$BASE"
    cat <<EOF > "$BASE/team.config.json"
{
  "member_count": $member_count,
  "my_role": "$my_role",
  "merge_strategy": "$merge_strat",
  "hosting": "$hosting"
}
EOF
  else
    dry_run_note "$BASE/team.config.json  [Team Configuration]"
  fi

  # Step 2: INTERFACES.md and TEAM.md
  step_banner 2 $TTOT "Contract Files" "INTERFACES.md + TEAM.md"
  write_template "templates/shared/schemas/interfaces.md" "$BASE/INTERFACES.md" --safe
  if ! $DRY_RUN; then
    echo "# Team Structure" > "$BASE/TEAM.md"
    echo "- Members: $member_count" >> "$BASE/TEAM.md"
    echo "- My Role: $my_role" >> "$BASE/TEAM.md"
  else
    dry_run_note "$BASE/TEAM.md  [Team Structure]"
  fi
  
  # Step 3: Agents and Commands
  step_banner 3 $TTOT "Role Agents & Commands" "Specialist agents per role + workflow commands"
  $DRY_RUN || mkdir -p "$BASE/agents" "$BASE/commands"
  for role in frontend backend database ml-data devops fullstack-lead; do
    write_template "templates/team-pack/agents/$role-specialist.md" "$BASE/agents/$role-specialist.md" --safe
  done
  write_template "templates/team-pack/agents/integration-reviewer.md" "$BASE/agents/integration-reviewer.md" --safe
  
  write_template "templates/team-pack/commands/team-setup.md" "$BASE/commands/team-setup.md" --safe
  write_template "templates/team-pack/commands/team-status.md" "$BASE/commands/team-status.md" --safe
  write_template "templates/team-pack/commands/team-sync.md" "$BASE/commands/team-sync.md" --safe
  write_template "templates/team-pack/commands/team-worktree.md" "$BASE/commands/team-worktree.md" --safe
  write_template "templates/team-pack/commands/team-handoff.md" "$BASE/commands/team-handoff.md" --safe
  
  # Step 4: Hooks and DevOps
  step_banner 4 $TTOT "Guard Hooks & DevOps" "interface-guard + contract-drift + DevOps pack"
  $DRY_RUN || mkdir -p "$BASE/hooks/scripts"
  write_template "templates/team-pack/hooks/scripts/interface-guard.sh" "$BASE/hooks/scripts/interface-guard.sh" --safe
  write_template "templates/team-pack/hooks/scripts/contract-drift.sh" "$BASE/hooks/scripts/contract-drift.sh" --safe
  $DRY_RUN || make_exec "$BASE/hooks/scripts/interface-guard.sh" || true
  $DRY_RUN || make_exec "$BASE/hooks/scripts/contract-drift.sh" || true
  
  write_template "templates/team-pack/commands/ci-setup.md" "$BASE/commands/ci-setup.md" --safe
  write_template "templates/team-pack/commands/env-audit.md" "$BASE/commands/env-audit.md" --safe
  write_template "templates/team-pack/DEPLOYMENT.md" "$BASE/DEPLOYMENT.md" --safe
  
  blank
  log "${GREEN}${BOLD}Team Pack setup complete.${RESET}"
}
