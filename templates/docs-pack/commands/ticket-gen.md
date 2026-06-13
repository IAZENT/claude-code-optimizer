---
name: ticket-gen
description: Generate Jira/Linear style tickets from PRD.md.
tools: Read, Write
model: claude-sonnet-4-6
---
Read `docs/PRD.md`.
Break down the requirements into actionable engineering tickets in markdown format.
Each ticket should have: Title, Priority, Description, Acceptance Criteria, and Technical Notes.
