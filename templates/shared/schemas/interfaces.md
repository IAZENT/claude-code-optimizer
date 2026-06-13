# Interface Contracts
<!-- Edited by whoever OWNS the interface. Everyone else: read-only,
     consume what's here, flag breaking changes via /team-sync. -->

## API Endpoints (owned by: backend)
| Method | Path              | Request body        | Response          | Status |
|--------|-------------------|----------------------|-------------------|--------|
| POST   | /api/auth/login   | {email, password}    | {token, user}     | stable |
| GET    | /api/users/:id    | -                     | User              | draft  |

## Database Schema (owned by: database)
| Table | Key columns                  | Notes                  |
|-------|-------------------------------|------------------------|
| users | id, email, password_hash      | unique index on email  |

## Shared Types (owned by: whoever defines first, others import)
- `User` — src/types/user.ts — { id, email, name, createdAt }

## ML/Data Contracts (owned by: ml-data)
| Endpoint/Function | Input shape | Output shape | Notes |

## Environment Variables (owned by: devops)
| Var | Used by | Required in |
