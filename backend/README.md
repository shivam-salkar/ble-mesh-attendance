# Backend — BLE Mesh Attendance

Backend infrastructure, database schemas, and cloud functions powered by Supabase and PostgreSQL.

## Architecture Overview

- **Database:** PostgreSQL managed via Supabase.
- **Authentication:** Supabase Auth (student and faculty roles to be introduced in a future phase).
- **Security:** Strict PostgreSQL Row Level Security (RLS) policies will be enforced on all tables.
- **Edge Functions:** Supabase Edge Functions (Deno / TypeScript) will handle server-side signature validation, session token issuance, and batch attendance ingestion.
- **Integrity Rule:** Attendance validation must **NOT** rely solely on client-side logic or client timestamps. All submissions must be authenticated and validated server-side against classroom session windows, cryptographic signatures, and gateway verification.

## Directory Structure

```
backend/
├── migrations/    # Version-controlled SQL migration scripts (Supabase CLI)
├── functions/     # Supabase Edge Functions (TypeScript/Deno)
├── seed/          # Development seed data for testing
└── README.md      # Backend architecture documentation
```

## Security & Credentials

> [!WARNING]
> Never commit real Supabase project URLs, API keys (anon or service_role), database passwords, or JWT secrets to this repository. All environment secrets must be configured via environment variables and local `.env` files (which are git-ignored).

- **Anon Key:** Can only be used with strictly locked-down RLS policies.
- **Service Role Key:** Restricted exclusively to trusted server environments (e.g. secure backend services or internal edge functions), never bundled in mobile apps or client firmware.

## Getting Started (Future Milestone)

When database schemas and functions are introduced, local development will use the Supabase CLI:

```bash
# Install Supabase CLI
npm install -g supabase

# Start local Supabase instance
supabase start

# Apply database migrations
supabase db reset
```
