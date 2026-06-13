import os

def write_file(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(content.strip() + "\n")

docs_dir = "templates/docs-pack/docs"
cmds_dir = "templates/docs-pack/commands"
agents_dir = "templates/docs-pack/agents"

# Docs
write_file(f"{docs_dir}/MEMORY_BANK.md", """# Project Memory Bank
Use this document to track overarching project goals, constraints, and historical context.

## Core Directives
- **Primary Goal**: [Insert goal]
- **Key Constraints**: [Insert constraints]

## Active Context
- **Current Phase**: [Insert phase]
- **Recent Decisions**:
  - [Date] - [Decision] - [Reasoning]

## Glossary
- `Term` - Definition
""")

write_file(f"{docs_dir}/PRD.md", """# Product Requirements Document (PRD)

## 1. Overview
[High-level summary of what is being built and why]

## 2. Target Audience
[Who is this for?]

## 3. User Stories
- As a [role], I want to [action] so that [value].

## 4. Scope
- **In Scope**:
- **Out of Scope**:

## 5. Success Metrics
- [Metric 1]
""")

write_file(f"{docs_dir}/ARCHITECTURE.md", """# System Architecture

## 1. High-Level Design
[Mermaid diagram or description of system components]

## 2. Tech Stack
- Frontend:
- Backend:
- Database:
- Infra:

## 3. Data Flow
[Describe how data moves through the system]

## 4. Cross-Cutting Concerns
- Authentication
- Logging
- Error Handling
""")

# Commands
write_file(f"{cmds_dir}/docs-init.md", """---
name: docs-init
description: Scaffolds the docs folder with PRD, Architecture, and Memory Bank templates.
tools: Bash, Write
model: claude-sonnet-4-6
---
Run `claude-optimize --docs` if not already installed.
Populate the templates in `docs/` by interviewing the user about their project.
""")

write_file(f"{cmds_dir}/docs-sync.md", """---
name: docs-sync
description: Syncs recent code changes into ARCHITECTURE.md and MEMORY_BANK.md.
tools: Read, Write, Bash
model: claude-sonnet-4-6
---
Review recent commits or `.claude/MEMORY.md`.
Update `docs/ARCHITECTURE.md` and `docs/MEMORY_BANK.md` with new structural decisions or context.
""")

write_file(f"{cmds_dir}/ticket-gen.md", """---
name: ticket-gen
description: Generate Jira/Linear style tickets from PRD.md.
tools: Read, Write
model: claude-sonnet-4-6
---
Read `docs/PRD.md`.
Break down the requirements into actionable engineering tickets in markdown format.
Each ticket should have: Title, Priority, Description, Acceptance Criteria, and Technical Notes.
""")

# Agents
write_file(f"{agents_dir}/technical-writer.md", """---
name: technical-writer
description: Agent responsible for generating, reviewing, and syncing project documentation.
tools: Read, Write, Edit, Bash
model: claude-sonnet-4-6
---
You are the TECHNICAL WRITER agent.
Your primary domain is the `docs/` folder.
Ensure all documentation follows the project's formatting rules.
When code architecture changes, you are responsible for updating ARCHITECTURE.md.
""")

# docs_pack.sh
docs_pack_sh = """
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
  local want_memory
  local want_prd
  local want_arch
  
  want_memory=$(ask_yn "Do you want a Project Memory Bank (MEMORY_BANK.md)?" "Y")
  want_prd=$(ask_yn "Generate a PRD template (PRD.md)?" "Y")
  want_arch=$(ask_yn "Generate an Architecture template (ARCHITECTURE.md)?" "Y")
  
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
"""
write_file("lib/packs/docs_pack.sh", docs_pack_sh)
print("Docs pack templates generated!")
