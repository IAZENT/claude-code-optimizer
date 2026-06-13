# Design System
<!-- Read automatically by the frontend-aesthetics skill for ANY UI work in
     this project. Run /project:design for a guided interview, or edit the
     ⚠️ EDIT THIS placeholders below directly. Keep under ~100 lines. -->

## Personality & Reference
<!-- ⚠️ EDIT THIS — 2-3 vibe words + 1-3 reference sites/brands/IDE themes ⚠️ -->
- Vibe: <!-- e.g. "brutalist editorial", "warm SaaS, confident" -->
- References (style only, never copy): <!-- e.g. "Linear, Vercel docs, Monokai" -->

## Typography
<!-- ⚠️ EDIT THIS — never Inter / Roboto / Open Sans / Lato / Arial / system-ui ⚠️ -->
- Display: <!-- e.g. Fraunces -->
- Body:    <!-- e.g. Bricolage Grotesque -->
- Mono:    <!-- e.g. JetBrains Mono -->
- Weight extremes: use e.g. 200 vs 800, not 400 vs 600
- Scale jumps of 3x+ between heading and body sizes, not 1.5x

## Color Palette
<!-- ⚠️ EDIT THIS — one dominant color + one sharp accent, defined as CSS vars ⚠️ -->
```css
:root {
  --color-primary:   #__EDIT__;
  --color-accent:    #__EDIT__;
  --color-bg:        #__EDIT__;
  --color-surface:   #__EDIT__;
  --color-text:      #__EDIT__;
}
```

## Spacing & Shape
- Base unit: <!-- e.g. 8px -->
- Radius:    <!-- e.g. 4px sharp / 24px soft — pick one and use everywhere -->
- Border/shadow style: <!-- e.g. 1px hairline borders, no drop shadows -->

## Component Conventions
<!-- e.g. "Buttons: solid --color-primary, no gradients, sharp 2px radius" -->

## Layout Rules
- Avoid the reflexive "3 equal cards in a row" unless content is genuinely
  3 parallel items — vary rhythm/density, use asymmetric grids or full-bleed
  sections instead.
- Subtle motion (hover/transition) over static flat cards.

## Do Not Use
- Inter, Roboto, Open Sans, Lato, Arial, or any system-ui font stack
- Purple-to-blue gradient hero sections on white or near-black backgrounds
- Generic "Built for the modern team" / stock SaaS hero copy
<!-- ⚠️ EDIT THIS — add anything specific to this brand/project ⚠️ -->

## Changelog
- [YYYY-MM-DD] Initial design system created
