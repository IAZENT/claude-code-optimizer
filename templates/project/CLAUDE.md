# ${PROJECT_NAME} — Claude Context
<!-- Keep under ~150 lines / ~40k tokens.
     Global style rules live in ~/.claude/CLAUDE.md — do NOT repeat here.
     This file = project-specific context only. -->

## Stack
<!-- ⚠️ EDIT THIS — replace with your actual stack before first use ⚠️ -->
- Runtime:   Node 22 / TypeScript 5.x
- DB:        PostgreSQL 16 + Drizzle ORM
- API:       Fastify 4, Zod validation
- Frontend:  Next.js 14, Tailwind CSS
- Auth:      <!-- Better Auth / NextAuth / Supabase Auth / JWT -->
- Infra:     <!-- Railway / Vercel / Fly.io / AWS / Docker -->
- Tests:     Vitest (unit), Playwright (E2E)

## Architecture
<!-- ⚠️ EDIT THIS — replace with your actual directory structure ⚠️ -->
\`\`\`
src/
  api/          # Routes → services → repositories
  services/     # Business logic — no DB access
  db/           # Schema + query helpers
  lib/          # Shared utilities — no business logic
  types/        # Global TypeScript types
\`\`\`

## Dev Commands
<!-- ⚠️ EDIT THIS — replace with your actual commands ⚠️ -->
- \`pnpm dev\`       dev server
- \`pnpm db:push\`   push schema (non-destructive)
- \`pnpm test\`      unit tests
- \`pnpm test:e2e\`  E2E tests
- \`pnpm lint\`      ESLint + tsc --noEmit

## Architecture Decisions (ADR)
<!-- Add entries as decisions are made — prevents Claude re-litigating them -->
<!-- Format: [YYYY-MM] Decision — Reason -->

## Rules
- All DB queries through repository layer — never in routes or services
- Errors: typed in services → caught in routes → RFC 7807 problem responses
- Tests required for all service-layer functions
- Parameterized queries only — never string interpolation near SQL

## ⛔ Never Do
- Never push directly to main — all changes via PR
- Never modify migration files after they've run
- Never use \`any\` type in TypeScript

## Frontend Aesthetics
- Any UI/page/component work: read ./DESIGN.md first (fonts, colors, spacing,
  Do Not Use list). The global frontend-aesthetics skill applies it automatically.
- No DESIGN.md yet? Run /project:design before generating any UI.

## Context Files
- .codesight/CONTEXT.md — codebase map (run: npx codesight --profile claude-code)
- .claude/MEMORY.md     — session decisions log
- DESIGN.md             — design system (fonts/colors/layout) for all UI work
