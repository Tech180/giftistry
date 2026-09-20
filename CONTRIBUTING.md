# Contributing

Thanks for helping with Giftistry packaging.

## Scope of this repository

| Change type | Where |
|-------------|--------|
| Docker Compose, Dockerfiles, nginx, `.env.example` | `docker/` |
| NixOS module, flake, sandbox SQL mirrors, examples | `nix/` |
| Install / backup / reverse-proxy docs | `docs/` |
| Product README / design assets | root / `design/` |
| API, SPA, theming engine | sibling repos (`giftistry-bun`, `giftistry-react`, `theming-engine`) |

## Before you start

1. Read [docs/install/docker.md](docs/install/docker.md) and [docs/install/nixos.md](docs/install/nixos.md).
2. Read [docs/schema.md](docs/schema.md) before editing `nix/sql/*`.
3. Prefer a focused PR.

## PR checklist

- [ ] Compose still validates (`docker compose -f docker/compose.yaml config`)
- [ ] Nix flake still evaluates (`nix flake check` in `nix/`)
- [ ] Docs updated if operator steps changed
- [ ] SQL mirrors updated only when synced with bun migrations (see schema.md)
