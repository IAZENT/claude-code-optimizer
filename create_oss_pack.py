import os

def write_file(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(content.strip() + "\n")

skills_dir = "templates/oss-pack/skills"

# Webapp Tester Skill
write_file(f"{skills_dir}/webapp-tester/SKILL.md", """---
name: webapp-tester
description: >
  Test web applications by spinning up a local server and navigating it with tools.
  Triggered by "test webapp", "run playwright", or "e2e tests".
tools: Bash, Read, Write
model: claude-sonnet-4-6
---
You are the WEBAPP TESTER.
1. Run `npm run build` and `npm start` (or the equivalent defined in CLAUDE.md) in the background.
2. Wait for the server to be ready on the local port.
3. If the Playwright MCP is enabled, use it to navigate to `http://localhost:<port>` and verify the UI matches DESIGN.md.
4. Report any visual discrepancies, console errors, or failed network requests.
""")

# Design System Skill
write_file(f"{skills_dir}/design-system/SKILL.md", """---
name: design-system
description: >
  Initialize or audit the project's design system tokens and components.
  Triggered by "setup design system", "audit UI", or "design tokens".
tools: Read, Write, Edit, Bash
model: claude-sonnet-4-6
---
You are the DESIGN SYSTEM EXPERT.
1. Read `DESIGN.md`.
2. Check `src/styles/` or equivalent CSS/Tailwind config to ensure the colors, typography, and spacing match DESIGN.md.
3. If setting up a new project, scaffold `index.css` or `tailwind.config.js` using the exact tokens from DESIGN.md.
4. Block any generic outputs (e.g. basic Inter, generic purple gradients) and enforce premium aesthetics.
""")

# oss_pack.sh
oss_pack_sh = """
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
"""
write_file("lib/packs/oss_pack.sh", oss_pack_sh)
print("OSS pack templates generated!")
