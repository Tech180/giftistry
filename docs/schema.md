# Schema authority

## Production

**Giftistry Bun owns the schema.** On API boot, [`runMigrations()`](../../giftistry-bun/src/common/database/migrations.ts) applies migrations to whatever database the process is configured to use (Compose volume, NixOS Postgres, external host).

Empty volume → start api → migrations run. Operators should not treat SQL files in this packaging repo as the production migrate path.

## Sandbox mirrors (`nix/sql/`)

| File | Role |
|------|------|
| `nix/sql/schema.sql` | Full schema seed for the Nix `devShell` local Postgres |
| `nix/sql/migrate-existing.sql` | Additive fixes applied by the shellHook when PG is already running |

These exist so `nix develop` can stand up a local DB without booting the API. Headers in those files require keeping them in sync with Bun.

## Sync checklist

When you change schema in **giftistry-bun**:

1. Update Bun `init-schema` / `migrations` (source of truth).
2. Mirror the change into `giftistry/nix/sql/schema.sql` and/or `migrate-existing.sql`.
3. Smoke-test: `cd giftistry/nix && nix develop` → start PG → `giftistry-db migrate` (or shellHook).
4. Smoke-test: empty Compose/NixOS DB → API boot → migrations succeed.

**CLI:** `giftistry-db ensure|init-schema|migrate|upgrade` (from `pkgs.giftistry` / `pkgs.giftistry-db`). Production still prefers API boot migrations over these SQL files.

## What not to do

- Do not apply `schema.sql` alone as the upgrade path for a live production database.
- Do not diverge sandbox SQL from Bun without updating both in the same change set.
