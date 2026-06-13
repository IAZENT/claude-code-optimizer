---
name: frontend-aesthetics
description: Use whenever generating, redesigning, or styling any UI, webpage, landing page, dashboard, or component — even if the request doesn't mention "design". Counters the default "AI slop" look (generic fonts, purple gradients, predictable 3-card layouts).
---
Without explicit direction, Claude converges on generic, "on-distribution" output —
the look users call "AI slop": Inter/Roboto/Arial/system fonts, purple-to-blue
gradients on white, evenly-spaced pastel cards, a hero that says "Built for the
modern team." Actively counter this.

## 0. Check for a project design system first
- If ./DESIGN.md exists, treat it as the source of truth: match its fonts, colors,
  spacing, and "Do Not Use" list exactly. Don't re-derive a new aesthetic.
- If it doesn't exist and this is a real project (not a one-off snippet), propose
  creating one — see the project's `/project:design` command.

## 1. Typography — commit, don't hedge
- Never default to Inter, Roboto, Open Sans, Lato, Arial, or system-ui.
- Pick ONE distinctive pairing and state it before coding, e.g. a display serif
  + geometric sans, or a variable font used across extreme weights.
- Use weight extremes (200 vs 800, not 400 vs 600) and size jumps of 3x+
  (not 1.5x) between heading and body.

## 2. Color & theme — commit, don't spread thin
- One dominant color + one sharp accent, not an evenly-distributed pastel palette.
- Forbidden default: purple/blue gradient hero on a white or near-black background.
- Define every color as a CSS variable (`--color-*`) so it's a single edit later.

## 3. Layout & motion
- Avoid the reflexive "3 equal cards in a row" pattern unless the content
  genuinely has 3 parallel items — vary rhythm and density instead.
- Prefer asymmetric grids, layered depth, or a full-bleed element somewhere
  over a perfectly centered, evenly-padded stack.
- Subtle motion (hover states, transitions) > static flat cards.

## 4. State the plan before coding
Output a one-line "design statement" (fonts, dominant color, layout idea) BEFORE
writing markup/CSS, so the choice reads as intentional — then build to it.

## 5. Iterate within the system, not around it
When asked to "make X stand out", propose a change that stays inside the
existing fonts/colors/spacing (e.g. "use a larger type-scale step or a
full-bleed `--color-primary` bar") rather than introducing a new ad-hoc style.
