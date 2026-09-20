# Docker Compose install

Run Giftistry as postgres + api + worker + web (nginx) with optional Mailpit for labs.

## Sibling layout

Compose builds from the **parent of this repo** (the `projects/` directory):

```text
projects/
  giftistry/          # this repo — run compose from giftistry/docker/
  giftistry-bun/
  giftistry-react/
  theming-engine/
```

## Quick start

```bash
cd giftistry/docker
cp .env.example .env
cp config/config.example.json config/config.json
# Edit .env — set PGPASSWORD and JWT_SECRET (≥ 32 characters, not a known default)
docker compose up -d --build
```

Open **http://localhost:8080** (or your `WEB_PORT`) and complete first-run setup.

## Environment

| Variable | Notes |
|----------|--------|
| `PGPASSWORD` | Required |
| `JWT_SECRET` | Required in production (≥ 32 chars). Or use `JWT_SECRET_FILE` / `CREDENTIALS_DIRECTORY` |
| `GIFTISTRY_PUBLIC_APP_URL` | Defaults to `http://localhost:${WEB_PORT:-8080}` — must match the browser origin |
| `WEB_PORT` | Host port for nginx (default `8080`) |
| `GIFTISTRY_ALLOW_SETUP` | First-run setup gate (default `true`) |

Config file: `./config/config.json` → `/etc/giftistry/config.json` in api/worker.

## Services

| Service | Role |
|---------|------|
| `postgres` | `postgres:16-alpine`, named volume, healthcheck |
| `api` | `GIFTISTRY_PROCESS_ROLE=api`, `/health` |
| `worker` | Same image, `src/worker.ts` |
| `web` | SPA + nginx; proxies `/api/`, `/ws/`, `/docs`, `/health` |
| `mailpit` | Profile `mail` only (labs) |

Schema is applied by the **API on boot** (`runMigrations`). Do not load `nix/sql/schema.sql` into the Compose volume as the sole migrate path — see [schema.md](../schema.md).

## Mailpit (optional)

```bash
docker compose --profile mail up -d
```

SMTP defaults in compose already point at `mailpit:1025`. UI: `http://localhost:8025`.

## Admin CLI

```bash
docker compose exec api bun run giftistry-admin --help
```

## Reverse proxy / backups

See [reverse-proxy.md](../reverse-proxy.md) and [backup.md](../backup.md).
