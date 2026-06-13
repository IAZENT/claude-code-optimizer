---
description: "Create or update DESIGN.md — the project's anti-generic design system"
argument-hint: "Optional: paste brand references / vibe words to skip the interview"
---
Goal: produce or refresh ./DESIGN.md, the single source of truth every UI
prompt in this project should be checked against (the frontend-aesthetics
skill reads it automatically).

If ./DESIGN.md exists: show its current Typography/Color/Layout sections,
ask only what needs to change, then update it (and add a Changelog line).

If it doesn't exist, run a short interview (skip anything $ARGUMENTS already
answers):
1. Vibe in 2-3 words (e.g. "brutalist editorial", "warm SaaS, confident")
2. 1-3 reference sites/brands/IDE themes for inspiration (style only, not copy)
3. One dominant color (hex or description) + one sharp accent
4. Display font + body font preference, or "you choose — just not Inter/Roboto/Arial"
5. Anything explicitly forbidden (e.g. "no purple gradients", "no rounded corners")

Then write ./DESIGN.md with sections: Typography, Color Palette (as CSS
variables), Spacing & Shape, Component Conventions, Layout Rules, Do Not Use,
Personality & Reference, Changelog. Apply the same anti-generic defaults as
the frontend-aesthetics skill (weight/size extremes, one dominant color +
accent, no Inter/Roboto/Arial/purple-gradients) for anything the interview
didn't specify. Keep it under 100 lines.
