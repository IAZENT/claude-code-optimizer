setup_docs_pack() {
  local BASE=".claude"
  local DTOT=3
  
  if [[ ! -d "$BASE" ]] && ! $DRY_RUN; then
    warn "Project must be initialized first. Run: claude-optimize --project"
    return 1
  fi
  
  section "Documentation Pack"
  
  # Step 1: Interview
  step_banner 1 $DTOT "Docs Configuration" "Choose which documents to scaffold"
  local want_memory=false
  local want_prd=false
  local want_arch=false
  
  if ask_yn "Do you want a Project Memory Bank (MEMORY_BANK.md)?" "Y"; then want_memory=true; fi
  if ask_yn "Generate a PRD template (PRD.md)?" "Y"; then want_prd=true; fi
  if ask_yn "Generate an Architecture template (ARCHITECTURE.md)?" "Y"; then want_arch=true; fi
  
  $DRY_RUN || mkdir -p "docs" "$BASE/docs-pack.installed"
  
  # Step 2: Templates
  step_banner 2 $DTOT "Scaffolding Docs" "Writing markdown templates to docs/"
  
  if $want_memory; then
    write_template "templates/docs-pack/docs/MEMORY_BANK.md" "docs/MEMORY_BANK.md" --safe
  fi
  if $want_prd; then
    write_template "templates/docs-pack/docs/PRD.md" "docs/PRD.md" --safe
  fi
  if $want_arch; then
    write_template "templates/docs-pack/docs/ARCHITECTURE.md" "docs/ARCHITECTURE.md" --safe
  fi
  
  # Step 3: Agents and Commands
  step_banner 3 $DTOT "Docs Agents & Commands" "writer agent + sync commands"
  $DRY_RUN || mkdir -p "$BASE/agents" "$BASE/commands"
  
  write_template "templates/docs-pack/agents/technical-writer.md" "$BASE/agents/technical-writer.md" --safe
  write_template "templates/docs-pack/commands/docs-init.md" "$BASE/commands/docs-init.md" --safe
  write_template "templates/docs-pack/commands/docs-sync.md" "$BASE/commands/docs-sync.md" --safe
  write_template "templates/docs-pack/commands/ticket-gen.md" "$BASE/commands/ticket-gen.md" --safe
  
  blank
  log "${GREEN}${BOLD}Docs Pack setup complete.${RESET}"
}
