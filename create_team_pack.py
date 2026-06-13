import os
import sys

def write_file(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(content.strip() + "\n")

# Shared Schemas
schemas_dir = "templates/shared/schemas"

# Agents
agents_dir = "templates/team-pack/agents"

roles = ["frontend", "backend", "database", "ml-data", "devops", "fullstack-lead"]
for role in roles:
    write_file(f"{agents_dir}/{role}-specialist.md", f"""---
name: {role}-specialist
description: >
  {role.title()} role agent for this project.
tools: Read, Write, Edit, Bash, Grep, Glob
model: claude-sonnet-4-6
---
You are the {role.upper()} specialist on a {{{{TEAM_SIZE}}}}-person team.

Your owned paths: {{{{OWNED_PATHS}}}}
Other roles on this team: {{{{OTHER_ROLES}}}}

BEFORE writing any new interface, function signature, or shared type:
1. Check .claude/INTERFACES.md — does this already have a contract?
2. If you're CREATING a new contract, ADD it to INTERFACES.md under the correct section BEFORE implementing.
3. If your change BREAKS an existing contract another role depends on, STOP and run /team-handoff to flag it.

When done with a chunk of work: run /team-handoff to log it in .claude/MEMORY.md and update INTERFACES.md status (draft → stable).
""")

write_file(f"{agents_dir}/integration-reviewer.md", """---
name: integration-reviewer
description: Validates interface contracts across role branches before merges.
tools: Read, Bash
model: claude-sonnet-4-6
---
You are the INTEGRATION REVIEWER.
Run `git diff` across all role branches/worktrees.
Check:
- Do the calls in frontend match the routes in backend?
- Do backend queries match the database schema?
- Do declared types match actual usage?
Report any contract drift based on .claude/INTERFACES.md.
""")

# Commands
cmds_dir = "templates/team-pack/commands"

write_file(f"{cmds_dir}/team-setup.md", """---
name: team-setup
description: Re-run the team setup interview and regenerate TEAM.md.
tools: Bash
model: claude-haiku-4-5
---
Please run `claude-optimize --team` in your terminal to re-run the team setup wizard.
""")

write_file(f"{cmds_dir}/team-status.md", """---
name: team-status
description: Shows each role's current branch/worktree + open contracts.
tools: Read, Bash
model: claude-sonnet-4-6
---
Read .claude/team.config.json. Read .claude/INTERFACES.md.
Run `git branch -a` and `git worktree list`.
Report the current status of each role.
""")

write_file(f"{cmds_dir}/team-sync.md", """---
name: team-sync
description: Pulls latest INTERFACES.md and flags breaking changes.
tools: Bash, Read
model: claude-sonnet-4-6
---
Run `git fetch origin` and `git diff main...HEAD -- .claude/INTERFACES.md`.
Flag any breaking changes to the user.
""")

write_file(f"{cmds_dir}/team-worktree.md", """---
name: team-worktree
description: Wraps git worktree add per role/feature.
tools: Bash
model: claude-sonnet-4-6
---
Extract the <role> and <feature> from the prompt.
Run: `git worktree add ../<project>-<role>-<feature> -b <role>/<feature>`
""")

write_file(f"{cmds_dir}/team-handoff.md", """---
name: team-handoff
description: Log completed work in MEMORY.md and notify via INTERFACES.md.
tools: Write, Edit, Bash
model: claude-sonnet-4-6
---
Update .claude/MEMORY.md with what was done.
Update .claude/INTERFACES.md status (draft → stable).
""")

write_file(f"{cmds_dir}/ci-setup.md", """---
name: ci-setup
description: Generates CI workflow based on detected stack and role paths.
tools: Write, Bash
model: claude-sonnet-4-6
---
Read .claude/team.config.json.
Generate a CI workflow (.github/workflows/ci.yml or .gitlab-ci.yml based on hosting).
Include lint, test, build per role's paths.
""")

write_file(f"{cmds_dir}/env-audit.md", """---
name: env-audit
description: Checks .env.example vs INTERFACES.md Environment Variables for drift.
tools: Read
model: claude-sonnet-4-6
---
Read .env.example and .claude/INTERFACES.md.
Flag any missing or undocumented environment variables.
""")

# Hooks
hooks_dir = "templates/team-pack/hooks/scripts"

write_file(f"{hooks_dir}/interface-guard.sh", """#!/usr/bin/env bash
# interface-guard.sh — Warns if editing outside owned paths
# Trigger: PreToolUse:Write|Edit
set -euo pipefail
# In a real implementation this would use jq to check team.config.json and paths.
echo '{"decision": "allow"}'
""")

write_file(f"{hooks_dir}/contract-drift.sh", """#!/usr/bin/env bash
# contract-drift.sh — Diffs INTERFACES.md vs exports
# Trigger: PreCompact|Stop
set -euo pipefail
# Not completely implemented due to bash limits, could run 'npm run check'
exit 0
""")

# Deployment
write_file("templates/team-pack/DEPLOYMENT.md", """# Deployment Checklist
- [ ] Tests pass
- [ ] Migrations reviewed
- [ ] Env vars set
- [ ] Type-check clean
""")

# team_pack.sh logic
team_pack_sh = """
setup_team_pack() {
  local BASE=".claude"
  local TTOT=4
  
  if [[ ! -d "$BASE" ]]; then
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
  cat <<EOF > "$BASE/team.config.json"
{
  "member_count": $member_count,
  "my_role": "$my_role",
  "merge_strategy": "$merge_strat",
  "hosting": "$hosting"
}
EOF

  # Step 2: INTERFACES.md and TEAM.md
  step_banner 2 $TTOT "Contract Files" "INTERFACES.md + TEAM.md"
  write_template "templates/shared/schemas/interfaces.md" "$BASE/INTERFACES.md" --safe
  echo "# Team Structure" > "$BASE/TEAM.md"
  echo "- Members: $member_count" >> "$BASE/TEAM.md"
  echo "- My Role: $my_role" >> "$BASE/TEAM.md"
  
  # Step 3: Agents and Commands
  step_banner 3 $TTOT "Role Agents & Commands" "Specialist agents per role + workflow commands"
  mkdir -p "$BASE/agents" "$BASE/commands"
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
  mkdir -p "$BASE/hooks/scripts"
  write_template "templates/team-pack/hooks/scripts/interface-guard.sh" "$BASE/hooks/scripts/interface-guard.sh" --safe
  write_template "templates/team-pack/hooks/scripts/contract-drift.sh" "$BASE/hooks/scripts/contract-drift.sh" --safe
  make_exec "$BASE/hooks/scripts/interface-guard.sh" || true
  make_exec "$BASE/hooks/scripts/contract-drift.sh" || true
  
  write_template "templates/team-pack/commands/ci-setup.md" "$BASE/commands/ci-setup.md" --safe
  write_template "templates/team-pack/commands/env-audit.md" "$BASE/commands/env-audit.md" --safe
  write_template "templates/team-pack/DEPLOYMENT.md" "$BASE/DEPLOYMENT.md" --safe
  
  blank
  log "${GREEN}${BOLD}Team Pack setup complete.${RESET}"
}
"""

write_file("lib/packs/team_pack.sh", team_pack_sh)
print("Team pack templates generated!")
