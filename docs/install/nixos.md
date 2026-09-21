# NixOS install

Giftistry ships as a **Nix package** (`pkgs.giftistry`) plus a **`services.giftistry`** module (systemd API/worker, optional local Postgres, optional local SPA via nginx).

**Edge / TLS / firewall are yours** unless you opt into `services.giftistry.web.enable` (local SPA + NixOS nginx on `web.port`). For production, prefer an external reverse proxy (Nginx Proxy Manager, Caddy, Traefik, …) — see [reverse-proxy.md](../reverse-proxy.md).

## Packages

| Attr | Contents |
|------|----------|
| `giftistry` (default) | API + worker + react sources, `share/giftistry-web`, `giftistry-db` |
| `giftistry-api` | API/worker (+ react/theming sources under `lib/`) |
| `giftistry-web` | Pure SPA placeholder (offline-friendly) |
| `giftistry-web-bundle` | Impure real SPA (`nix build .#giftistry-web-bundle --impure`) |
| `giftistry-db` | CLI: `ensure` / `init-schema` / `migrate` / `upgrade` |

```bash
cd giftistry/nix
nix build .#giftistry
# result/bin/giftistry-api, giftistry-worker, giftistry-db
# result/share/giftistry-web
```

### Updating Postgres

| Situation | Command |
|-----------|---------|
| Create DB if missing | `giftistry-db ensure` |
| Fresh sandbox schema | `giftistry-db init-schema` |
| Additive sandbox SQL | `giftistry-db migrate` or `giftistry-db upgrade` |
| **Production** | Start/restart `giftistry-api` — Bun `runMigrations()` / `initializeSchema()` on boot |

Honours `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE`. See [schema.md](../schema.md).

## Flake input

```nix
giftistry = {
  url = "path:/home/you/Documents/projects/giftistry/nix";
  # Or: url = "github:YOUR_ORG/giftistry?dir=nix";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Override app sources when not using local `git+file://` defaults:

```nix
giftistry.inputs.giftistry-bun.url = "github:YOUR_ORG/giftistry-bun";
giftistry.inputs.giftistry-react.url = "github:YOUR_ORG/giftistry-react";
giftistry.inputs.theming-engine.url = "github:YOUR_ORG/theming-engine";
```

## Enable the module

**API only** (recommended behind NPM / external proxy):

```nix
{
  nixpkgs.overlays = [ inputs.giftistry.overlays.default ];
  imports = [ inputs.giftistry.nixosModules.giftistry ];

  services.giftistry = {
    enable = true;
    package = pkgs.giftistry;
    publicAppUrl = "https://gifts.example.com"; # browser-facing origin
    web.enable = false; # do not start NixOS nginx for Giftistry
    # jwtSecretFile = config.sops.secrets.giftistry-jwt.path; # optional; else auto under stateDir
  };
}
```

**Local SPA + nginx** (laptop / quick try — optional):

```nix
services.giftistry = {
  enable = true;
  publicAppUrl = "http://127.0.0.1:3000";
  web.enable = true;   # default in module
  web.port = 3000;     # nginx; API stays on port 3001
};
```

Full snippet: [`nix/examples/configuration.nix`](../../nix/examples/configuration.nix). Put `config.json` at `/etc/giftistry/config.json` (the `giftistry` user must be able to **write** it — the module tmpfiles rules chown `/etc/giftistry`).

## Options

| Option | Default | Behavior |
|--------|---------|----------|
| `enable` | — | API (+ worker) units |
| `package` | `pkgs.giftistry` | Bundle (API/worker/web sources + `giftistry-db`) |
| `enableWorker` | `true` | `giftistry-worker.service` |
| `publicAppUrl` | required | CORS / emails / WebAuthn (browser origin) |
| `port` | `3001` | API listen port |
| `web.enable` | `true` | Build SPA + NixOS nginx proxy on `web.port` |
| `web.port` | `3000` | nginx listen port when `web.enable` |
| `web.root` | `/var/cache/giftistry-web` | Built SPA files for nginx |
| `configFile` | `/etc/giftistry/config.json` | Config path (must be writable by service user) |
| `stateDir` | `/var/lib/giftistry` | State + Bun `node_modules` + JWT auto-file |
| `jwtSecretFile` | `null` | Optional `LoadCredential` → `JWT_SECRET`. When unset, Bun auto-persists `${stateDir}/jwt_secret` |
| `credentialsDirectory` | `null` | Extra credentials dir |
| `database.createLocal` | `true` | `ensureDatabases` / `ensureUsers` only |
| `database.*` | — | External host / password file |
| `environment` | `{}` | Extra unit env |

**Not managed unless `web.enable`:** host firewall, ACME, and any reverse proxy other than the optional NixOS nginx vhost — see [reverse-proxy.md](../reverse-proxy.md).

**Secrets:** Prefer sops-nix (or similar) for `jwtSecretFile` on multi-host setups. If omitted, Bun writes `${stateDir}/jwt_secret` on first boot (back up `stateDir`).

**Web assets:** With `web.enable`, prepare builds the React app into `web.root`. With `web.enable = false`, serve a real SPA yourself (`giftistry-web-bundle --impure`, Docker `giftistry-web`, etc.). Pure `giftistry-web` in the package is only a placeholder HTML page.

## Dev shell

```bash
cd giftistry/nix && nix develop
# giftistry-db is on PATH
```

## Upgrades

1. Update flake inputs.
2. `nixos-rebuild switch`.
3. API `ExecStartPre` re-syncs the app tree when the package path changes; `giftistry-web-build` rebuilds the SPA when `web.enable` and the package stamp changes.
4. API applies DB schema/migrations on boot (or run `giftistry-db migrate` for sandbox SQL only).
