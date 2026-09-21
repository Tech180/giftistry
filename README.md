<p align="center">
  <img src="design/logo.svg" alt="Giftistry" width="120" />
</p>

<h1 align="center">Giftistry</h1>

<p align="center">
  <strong>Self-hosted wishlists that stay private, shareable, and actually useful.</strong>
</p>

<p align="center">
  <a href="#"><img alt="License" src="https://img.shields.io/badge/license-TODO-blue.svg" /></a>
  <a href="#"><img alt="Status" src="https://img.shields.io/badge/status-early%20access-orange.svg" /></a>
  <a href="#"><img alt="Deploy" src="https://img.shields.io/badge/deploy-docker%20%7C%20nixos-blueviolet.svg" /></a>
</p>

<p align="center">
  <a href="#features">Features</a> ·
  <a href="#getting-started">Getting started</a> ·
  <a href="#documentation">Docs</a> ·
  <a href="#contributing">Contributing</a>
</p>

---

Giftistry helps people collect gifts, share lists with friends and family, and coordinate claims — without stuffing your data into someone else's SaaS.

This repository is the **homelab / packaging** entry point (Docker Compose + NixOS). Application source lives in sibling repos (`giftistry-bun`, `giftistry-react`, `theming-engine`); operators deploying with Docker only need **this** repo.

> **Note**  
> Screenshots and a public demo URL go here when you have them. Immich/Jellyfin-style READMEs lead with a visual — one hero image beats three paragraphs.

## Features

| | |
| :--- | :--- |
| **Wishlists** | Create lists, shares, invites, export/PDF, rollover |
| **Claims** | Coordinate gifts so nobody doubles up |
| **Auth** | Passwords, passkeys, 2FA, OIDC/SSO |
| **Jobs** | Background import / enrich / summarize with realtime progress |
| **Privacy-first** | You host the stack; you keep the data |

## Getting started

### Docker Compose (recommended)

```bash
git clone https://github.com/Tech180/giftistry.git
cd giftistry/docker
cp .env.example .env
cp config/config.example.json config/config.json
# Edit .env — set PGPASSWORD (JWT_SECRET optional)
docker compose up -d
```

Open **http://localhost:8080** and complete first-run setup. Images pull from GHCR (`giftistry-server`, `giftistry-web`).

To use your own Postgres instead of the bundled one, comment out `COMPOSE_PROFILES=db` in `.env` and set `PGHOST`.

Full guide: [docs/install/docker.md](docs/install/docker.md).

### NixOS

Import the package overlay + module. The API listens on a port (default 3001); **you** own TLS / firewall / reverse proxy (Nginx Proxy Manager, Caddy, Traefik, host nginx, …). Optional `web.enable` can start a local NixOS nginx SPA for sandboxing — not required for production.

```nix
nixpkgs.overlays = [ inputs.giftistry.overlays.default ];
imports = [ inputs.giftistry.nixosModules.giftistry ];
services.giftistry = {
  enable = true;
  package = pkgs.giftistry;
  publicAppUrl = "https://gifts.example.com";
  web.enable = false; # use NPM / external proxy; set true for local :3000 SPA
  # jwtSecretFile = "/run/secrets/giftistry-jwt"; # optional; else auto under stateDir
};
```

Full guide: [docs/install/nixos.md](docs/install/nixos.md). Edge paths: [docs/reverse-proxy.md](docs/reverse-proxy.md). Example: [nix/examples/configuration.nix](nix/examples/configuration.nix).

## Documentation

| Doc | What it's for |
| --- | --- |
| [Docker install](docs/install/docker.md) | Pull images, env, external DB, Mailpit |
| [NixOS install](docs/install/nixos.md) | Package + module, giftistry-db, your proxy |
| [Schema](docs/schema.md) | Bun migrations vs sandbox SQL mirrors |
| [Reverse proxy](docs/reverse-proxy.md) | NPM / Caddy / Traefik / host nginx |
| [Backup](docs/backup.md) | Postgres + state + config |
| [Development](docs/development.md) | `nix develop`, sibling app repos |

## Stack

- **API / worker:** Bun + Elysia + PostgreSQL  
- **Web:** React (Vite); Docker image or optional NixOS nginx serves the SPA  
- **Realtime:** WebSockets + Postgres LISTEN/NOTIFY  
- **Deploy:** Docker Compose (GHCR) or NixOS systemd  

## Contributing

- **Packaging, Compose, NixOS module, install docs** → this repo ([CONTRIBUTING.md](CONTRIBUTING.md)).
- **API / web / themes** → the sibling application repositories.

## License

TODO — add your license (e.g. AGPL / MIT / proprietary) and link the full text.
