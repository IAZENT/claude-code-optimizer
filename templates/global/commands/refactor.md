---
description: "Safe refactor — structure only, zero behavior change"
---
Refactor target: $ARGUMENTS

Rules:
- Restructure ONLY — no behavior change, no new features, public interface unchanged
- Tests must still pass after (run them to verify)
- Show before/after diff
- Name the pattern: // Extract Method · // Move to Service · // Strategy Pattern
- Flag risks: // ⚠️ potential behavior change — verify
