<div align="center">
  <h1>⚡ Claude Code Optimizer v1.0.0</h1>
  <p><b>The ultimate modular framework for token economy, multi-agent workflows, and safety inside Claude Code.</b></p>
  
  [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
  [![Bash](https://img.shields.io/badge/Language-Bash-4EAA25.svg)](https://gnu.org/software/bash/)
  [![Claude Code](https://img.shields.io/badge/Optimized_for-Claude_Code-D97757.svg)](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview)
  [![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](http://makeapullrequest.com)

  <p><i>Maximize output quality. Minimize token drain. Built for solo developers and growing teams.</i></p>
</div>

---

## 💡 The Problem

[Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview) is an incredibly powerful CLI agent, but by default, it can be **expensive** and **noisy**. It aggressively reads terminal output (including ANSI color codes and progress bars), re-reads its entire context on every turn, and can quickly bloat its memory with stale tasks. Without guardrails, you will burn through your API limits rapidly.

## 🚀 The Solution

**Claude Code Optimizer v1.0.0** is a production-grade, highly modular bash framework that configures your machine and projects for **maximum token efficiency and robust team collaboration**. 

Running this script injects a battle-tested stack of **hooks, skills, specialized agents, slash commands, and third-party tools** into your global and local `.claude/` environments. Users save **60-90%** on token costs without sacrificing reasoning capability.

---

## ✨ Core Features

- 🧠 **Token Economy Engine:** Features Chain-of-Draft (`/user:chain-of-draft`) and Caveman (`[caveman]`) modes to enforce ultra-lean AI reasoning outputs, saving thousands of tokens per session.
- 🚧 **Smart Interception Hooks:** 
  - `read-once.sh`: Blocks Claude from re-reading unchanged files.
  - `compact-output.sh`: Intelligently strips ANSI noise and truncates massive terminal outputs (like `npm test` or `git log`).
  - `cost-guard.sh`: Warns you when you hit 80% of your daily token budget.
- ⚙️ **Strict Effort Control:** Built-in hooks (`effort-gate-pre`/`effort-gate-post`) that give teeth to your intent. Using `/user:effort-low` blocks expensive commands like `docker build` and restricts API calls.
- 🧹 **Context & Memory Hygiene:** Auto-generates aggressive `.claudeignore` blocks, prunes stale `MEMORY.md` logs via `token-trim`, and facilitates clean checkpointing with the `/user:handoff` command.
- 📦 **Smart Tool Integrations:** Auto-installs 2026's best token-saving tools like `codesight` (semantic indexing) and `rtk` (Rust Token Killer).

---

## 📦 Optional Workspaces (Packs)

Claude Code Optimizer has evolved from a configuration script into a fully modular framework. Launch the interactive wizard to install any of these workflow packs:

- 👥 **Team Pack (`--team`)**: Scales Claude for 2-8 person teams. Auto-generates specialized agents (`frontend-specialist`, `devops-specialist`, etc.) and a strict `INTERFACES.md` contract. Includes `interface-guard.sh` to prevent Claude from making changes outside your assigned domain.
- 📚 **Docs Pack (`--docs`)**: Deploys a dedicated `technical-writer` agent. Scaffolds `PRD.md`, `ARCHITECTURE.md`, and `MEMORY_BANK.md`. Includes `/user:ticket-gen` to automatically translate PRDs into actionable Linear/Jira engineering tickets.
- 🛠️ **OSS Skill Pack (`--oss-pack`)**: Injects vetted community skills directly into your global setup. Includes `webapp-tester` (for automated Playwright e2e validation) and `design-system` (to block generic AI UI outputs and enforce premium aesthetics).

---

## 🚀 Installation

**Recommended (via PyPI):**
```bash
pip install claudeoptimize
```

**Alternative (Bash Installer):**
This script requires zero external dependencies to run. 

```bash
# 1. Download the script
curl -fsSL https://raw.githubusercontent.com/IAZENT/claude-code-optimizer/main/claude-optimize.sh -o claude-optimize.sh

# 2. Make it executable
chmod +x claude-optimize.sh

# 3. Run the interactive installer globally
./claude-optimize.sh --install
```

---

## 💻 Usage

Once installed globally, you can initialize any project or update your global settings effortlessly.

### Fast Track
The recommended first-time setup command:
```bash
claude-optimize --both --yes
```
*(Installs the global `~/.claude/` config, initializes the current directory, and auto-installs the recommended token-saver CLI tools).*

### CLI Commands

| Command | Description |
|---|---|
| `claude-optimize` | Interactive setup menu (Global, Project, Team, Docs, OSS). |
| `claude-optimize --both` | Quick setup for global + current project. |
| `claude-optimize --team` | Initialize the multi-agent Team Collaboration Pack. |
| `claude-optimize --docs` | Scaffold the PRD and Architecture Docs Pack. |
| `claude-optimize --oss-pack` | Install vetted open-source workflow skills. |
| `claude-optimize --budget 150000` | Sets your daily token ceiling to 150k (used by the cost-guard hook). |
| `claude-optimize --analyze` | Parses local logs to show your top token-burning projects today. |
| `claude-optimize --status` | Checks your machine's optimization health and pack installation status. |
| `claude-optimize --update` | Pulls the latest templates and components from GitHub and self-updates. |

---

## 🛠️ The Commands You Get

Once optimized, you unlock a suite of powerful workflow commands directly inside Claude Code:

### Core Workflows
- **`/user:plan`** — Numbered plan, no code until you confirm.
- **`/user:debug`** — Root cause + minimal fix, skips the exploratory noise.
- **`/user:compress`** — Checkpoints your current state into `MEMORY.md` so you can safely `/compact`.
- **`/user:handoff`** — Gracefully saves your session state and unmerged changes before a full context clear.
- **`/user:claude-md-audit`** — Audits your project files to strip inferable boilerplate and save prompt tokens.

### Token Economy
- **`/user:chain-of-draft`** — 80-90% fewer reasoning tokens (CoD mode).
- **`/user:effort-low`** — Triggers a lean session (Chain-of-Draft + no subagents + blocks heavy execution).
- **`/user:effort-high`** — Triggers a deep session (full reasoning + architectural subagents allowed).
- **`/user:budget-check`** — Live report on your daily token spend and context health.

---

## 🤝 Contributing

Contributions are welcome! If you've found a new way to shave off tokens, discovered a new plugin, or wrote a better hook:

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

## 📜 License

Distributed under the MIT License. See `LICENSE` for more information.

---
<div align="center">
  <i>Built to make AI coding sustainable.</i>
</div>
