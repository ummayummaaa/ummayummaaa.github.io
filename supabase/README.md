# Supabase baseline

This directory records the current production structure for project
`hfgiknokcjrwyddflmtq` without applying any schema change to production.

## Initial migration

`migrations/20260922153500_remote_schema.sql` was generated from the production
`public` schema on 2026-09-22 with ownership and ACL statements omitted. It is
the authoritative baseline for future migrations. The older standalone SQL
files outside this repository remain historical source material and must not be
replayed as a replacement for this baseline.

The migration was applied to an isolated PostgreSQL 17 test database containing
the Supabase managed `auth`, `storage`, and `realtime` schemas. The following
object counts matched production exactly:

| Object type | Production | Restored migration |
| --- | ---: | ---: |
| Public tables | 16 | 16 |
| Public functions | 23 | 23 |
| Public RLS policies | 24 | 24 |
| Public triggers | 5 | 5 |

No data statements are present in the migration. No SQL from the migration was
executed against production during capture or verification.

## Future changes

Create every later schema change as a new timestamped file in `migrations/`.
Review and test it in an isolated database before applying it to production.
Do not edit the baseline merely to represent a later production change.

The `functions/` directory is intentionally empty because the project currently
has no Edge Functions.
