# Backup and restore

## What to back up

| Asset | Compose | NixOS |
|-------|---------|--------|
| PostgreSQL | `postgres_data` volume | local cluster or external DB |
| App state | `giftistry_data` → `/var/lib/giftistry` | `services.giftistry.stateDir` |
| Config | `docker/config/config.json` | `/etc/giftistry/config.json` |
| Secrets | `.env` / secret files; auto JWT at `giftistry_data` → `/var/lib/giftistry/jwt_secret` | `jwtSecretFile` or `${stateDir}/jwt_secret` when auto |

## Dump the database

**Compose**

```bash
cd giftistry/docker
docker compose exec -T postgres \
  pg_dump -U "${PGUSER:-giftistry}" "${PGDATABASE:-giftistry}" \
  > giftistry-$(date +%Y%m%d).sql
```

**NixOS (local postgres)**

```bash
sudo -u postgres pg_dump giftistry > giftistry-$(date +%Y%m%d).sql
# or as the giftistry role over the unix socket
```

## Restore order

1. Restore `config.json` and secrets.
2. Start Postgres (empty or existing).
3. Restore the SQL dump into the Giftistry database.
4. Restore `/var/lib/giftistry` (or the Compose data volume) if you rely on files stored there.
5. Start api → worker → web. The API may run additive migrations on boot; a full dump already includes schema.

Do **not** apply `nix/sql/schema.sql` on top of a restored production dump unless you know you need a sandbox re-seed.

## Config and secrets

Keep DB passwords out of the database dump. The auto-generated JWT lives in the **app state volume** (`/var/lib/giftistry/jwt_secret`) — include that volume in backups. Rotating JWT (delete the file, change `JWT_SECRET`, or replace `jwtSecretFile`) invalidates existing sessions/tokens.
