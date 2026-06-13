<div align="center">
  <h1>⚡ Claude Code Optimizer</h1>
  <p><b>The ultimate, zero-cost token economy and workflow stack for Claude Code</b></p>
  
  [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
  [![Bash](https://img.shields.io/badge/Language-Bash-4EAA25.svg)](https://gnu.org/software/bash/)
  [![Claude Code](https://img.shields.io/badge/Optimized_for-Claude_Code-D97757.svg)](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview)
  [![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](http://makeapullrequest.com)

  <p><i>Maximize output quality. Minimize token drain. Built for solo developers and small teams.</i></p>
</div>

---

## 💡 The Problem

[Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview) is an incredibly powerful CLI agent, but by default, it can be **expensive**. It aggressively reads terminal output (including ANSI color codes and progress bars), re-reads its entire context on every turn, and can quickly bloat its memory with stale tasks, causing you to burn through your API limits or billing blocks.

## 🚀 The Solution

**Claude Code Optimizer** is a single bash script that configures your machine and your projects for **maximum token efficiency**. 

Running this script injects a battle-tested stack of **hooks, skills, slash commands, and third-party tools** into your `~/.claude/` directory, saving you **60-90%** on token costs without sacrificing reasoning capability.

---

## ✨ Features

- 🛑 **Cost Guard:** A pre-tool hook that monitors your daily token usage via local JSONL logs. It warns you when you hit 80% of your daily budget, preventing accidental bill shock.
- 🧠 **Chain-of-Draft (CoD):** A built-in `/user:chain-of-draft` command and `[lean]` skill that forces Claude to use ≤5-word bullet points for internal reasoning, drastically cutting down on output tokens.
- ✂️ **Token Trim:** Auto-prunes stale decisions from your `MEMORY.md` when it exceeds 100 lines, killing context rot before it starts.
- 🛑 **Context Bloat Protection:** Auto-generates an aggressive `.claudeignore` to block Claude from reading `node_modules`, `dist`, and cached outputs, saving thousands of tokens per file-system exploration.
- 📦 **Smart Tool Integrations:** Auto-installs and configures 2026's best token-saving tools:
  - `rtk` (Rust Token Killer): Strips ANSI and noise from CLI outputs.
  - `claude-token-saver`: Real-time prompt caching TTL monitoring.
  - `codesight`: Semantically indexes your repository, reducing file reads by up to 13x.
- 🛡️ **Safety & Security:** Pre-configured `block-secrets.sh` hook prevents API keys and Bearer tokens from ever being sent to the AI.

---

## 📦 Installation

This script requires zero external dependencies to run. 

```bash
# 1. Download the script
curl -fsSL https://raw.githubusercontent.com/IAZENT/claude-code-optimizer/main/claude-optimize.sh -o claude-optimize.sh

# 2. Make it executable
chmod +x claude-optimize.sh

# 3. Run the interactive installer
./claude-optimize.sh
```

**To install it globally** so you can run it anywhere:
```bash
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
| `claude-optimize --both` | Interactive setup for global + current project. |
| `claude-optimize --global` | Updates `~/.claude/` configuration only. |
| `claude-optimize --project` | Initializes the current directory (or path) for Claude Code. |
| `claude-optimize --budget 150000` | Sets your daily token ceiling to 150k (used by the cost-guard hook). |
| `claude-optimize --analyze` | Parses local logs to show your top token-burning projects today. |
| `claude-optimize --upgrade` | Safely adds new features to an existing setup without overwriting files. |
| `claude-optimize --status` | Checks your machine's optimization health. |

---

## 🛠️ The Commands You Get

Once optimized, you get access to powerful new slash commands inside Claude Code:

- **`/user:effort-low`** — Triggers a lean session (Chain-of-Draft reasoning + no subagents + direct answers).
- **`/user:effort-high`** — Triggers a deep session (full reasoning + architectural subagents).
- **`/user:budget-check`** — Live report on your daily token spend and context health.
- **`/user:compress`** — Checkpoints your current state into `MEMORY.md` so you can safely run `/compact` without losing momentum.
- **`/user:debug`** — Root cause analysis + minimal fix (skips verbose exploratory noise).

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
