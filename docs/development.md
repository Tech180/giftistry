# Development

## Repos

```text
projects/
  giftistry/          # packaging (this repo)
  giftistry-bun/      # API + worker
  giftistry-react/    # web SPA
  theming-engine/     # theme CSS
```

## Local Postgres sandbox

From the packaging flake:

```bash
cd giftistry/nix
nix develop
pg_ctl start -l "$PGDATA/server.log" -o "-k $PGDATA"
```

Or from a host flake that re-exports this shell (`nix develop .#giftistry`).

The shellHook initializes PGDATA and applies `nix/sql/schema.sql` / `migrate-existing.sql`. Those files are **mirrors for the sandbox only** — see [schema.md](schema.md).

## Run the apps

```bash
# terminal 1 — API (from giftistry-bun, inside nix develop)
cd ../giftistry-bun
bun install
bun run dev

# terminal 2 — worker
bun run dev:worker

# terminal 3 — web
cd ../giftistry-react
bun install
bun run dev
```

Architecture notes live in the app repos (domain / use-cases / infrastructure). Packaging and deploy docs stay here.

## Production-like stack

Use [install/docker.md](install/docker.md) for a full compose stack on the same sibling layout.
