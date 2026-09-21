# Docker Compose install

Pull prebuilt images from GHCR. You only need this packaging repo — not `giftistry-bun` / `giftistry-react` / `theming-engine` on the server.

## Quick start

```bash
git clone https://github.com/Tech180/giftistry.git
cd giftistry/docker
cp .env.example .env
cp config/config.example.json config/config.json
# Edit .env — set PGPASSWORD (JWT_SECRET optional; auto-persisted if omitted)
docker compose up -d
```

Open **http://localhost:8080** (or your `WEB_PORT`) and complete first-run setup.

Upgrade later:

```bash
# bump GIFTISTRY_VERSION in .env if needed
docker compose pull
docker compose up -d
```

## Environment

| Variable | Notes |
|----------|--------|
| `GHCR_OWNER` | Image namespace (default `tech180`; must be lowercase for Docker) |
| `GIFTISTRY_VERSION` | Image tag pin (e.g. `v0.0.22`) |
| `COMPOSE_PROFILES` | Default `db` starts bundled Postgres. **Comment out this one line** to use an external/local DB |
| `PGHOST` | Default `postgres` (compose service). Set to `host.docker.internal` or your DB host when `db` profile is off |
| `PGPASSWORD` | Required when profile `db` is on (bundled Postgres) |
| `JWT_SECRET` | Optional. If unset, Bun auto-generates and writes `/var/lib/giftistry/jwt_secret` on the data volume. Or use `JWT_SECRET_FILE` / credentials dir. Set `GIFTISTRY_AUTO_JWT_SECRET=false` to require an explicit secret |
| `GIFTISTRY_PUBLIC_APP_URL` | Must match the browser origin |
| `WEB_PORT` | Host port for nginx (default `8080`) |
| `GIFTISTRY_ALLOW_SETUP` | First-run setup gate (default `true`) |

Config file: `./config/config.json` → `/etc/giftistry/config.json` in api/worker.

## External / host Postgres

1. Comment out `COMPOSE_PROFILES=db` in `.env`.
2. Set `PGHOST` (and `PGPORT` / `PGUSER` / `PGPASSWORD` / `PGDATABASE`) to your database.
3. Create an empty database; the API applies migrations on boot (`runMigrations`). Do not load `nix/sql/schema.sql` as the sole production migrate path — see [schema.md](../schema.md).

## Services

| Service | Image / role |
|---------|----------------|
| `postgres` | `postgres:16-alpine`, profile `db` |
| `api` | `ghcr.io/…/giftistry-server`, role `api` |
| `worker` | Same server image, `src/worker.ts` |
| `web` | `ghcr.io/…/giftistry-web`, SPA + nginx proxy |
| `mailpit` | Profile `mail` only (labs) |

## Mailpit (optional)

```bash
docker compose --profile mail up -d
# or add mail to COMPOSE_PROFILES=db,mail
```

SMTP defaults point at `mailpit:1025`. UI: `http://localhost:8025`.

## Admin CLI

```bash
docker compose exec api bun run giftistry-admin --help
```

## Build from source (maintainers)

Sibling layout next to this repo (`giftistry-bun`, `giftistry-react`, `theming-engine`), then:

```bash
cd giftistry/docker
docker compose -f compose.yaml -f compose.build.yaml up -d --build
```

The web image builds `theming-engine` first so `sync:theme-catalog` can run during `bun run build`.

CI publishes images on `v*` tags — see `.github/workflows/publish-images.yml` and `docker/versions.env`. Private app repos need a repo secret `APP_REPO_TOKEN` with read access.

## Reverse proxy / backups

See [reverse-proxy.md](../reverse-proxy.md) and [backup.md](../backup.md).
