# NixOS install

Giftistry ships as a **Nix package** (`pkgs.giftistry`) plus a thin **`services.giftistry`** module (systemd API/worker, optional local Postgres role/DB). It does **not** configure nginx, firewall, or TLS — wire those in your host.

## Packages

| Attr | Contents |
|------|----------|
| `giftistry` (default) | API + worker sources, `share/giftistry-web`, `giftistry-db` |
| `giftistry-api` | API/worker only |
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
| **Production** | Start/restart `giftistry-api` — Bun `runMigrations()` on boot |

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

```nix
{
  nixpkgs.overlays = [ inputs.giftistry.overlays.default ];
  imports = [ inputs.giftistry.nixosModules.giftistry ];

  services.giftistry = {
    enable = true;
    package = pkgs.giftistry;
    publicAppUrl = "https://gifts.example.com";
    jwtSecretFile = config.sops.secrets.giftistry-jwt.path;
  };

  # You own the edge — example:
  # services.nginx.virtualHosts."gifts.example.com" = {
  #   root = "${pkgs.giftistry}/share/giftistry-web";
  #   locations."/api/".proxyPass = "http://127.0.0.1:3001";
  #   ...
  # };
}
```

Full snippet: [`nix/examples/configuration.nix`](../../nix/examples/configuration.nix). Put `config.json` at `/etc/giftistry/config.json`.

## Options

| Option | Default | Behavior |
|--------|---------|----------|
| `enable` | — | API (+ worker) units |
| `package` | `pkgs.giftistry` | Bundle (front/back + `giftistry-db`) |
| `enableWorker` | `true` | `giftistry-worker.service` |
| `publicAppUrl` | required | CORS / emails / WebAuthn |
| `port` | `3001` | API listen port |
| `configFile` | `/etc/giftistry/config.json` | Config path |
| `stateDir` | `/var/lib/giftistry` | State + Bun `node_modules` |
| `jwtSecretFile` | required | `LoadCredential` → `JWT_SECRET` |
| `credentialsDirectory` | `null` | Extra credentials dir |
| `database.createLocal` | `true` | `ensureDatabases` / `ensureUsers` only |
| `database.*` | — | External host / password file |
| `environment` | `{}` | Extra unit env |

**Not in this module:** nginx, ACME, firewall ports — configure those yourself (see [reverse-proxy.md](../reverse-proxy.md)).

**Secrets:** sops-nix (or similar) for `jwtSecretFile`. systemd sets `CREDENTIALS_DIRECTORY`.

**Web assets:** pure `giftistry-web` is a placeholder. For a real SPA, build `giftistry-web-bundle --impure` and override the web input of the umbrella, or serve Compose-built assets. Point your proxy `root` at `${pkgs.giftistry}/share/giftistry-web`.

## Dev shell

```bash
cd giftistry/nix && nix develop
# giftistry-db is on PATH
```

## Upgrades

1. Update flake inputs.
2. `nixos-rebuild switch`.
3. API `ExecStartPre` re-syncs the app tree when the package path changes.
4. API applies DB migrations on boot (or run `giftistry-db migrate` for sandbox SQL only).
