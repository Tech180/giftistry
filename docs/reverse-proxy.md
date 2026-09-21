# Reverse proxy

Giftistry expects a **single public origin** (`GIFTISTRY_PUBLIC_APP_URL` / `services.giftistry.publicAppUrl`) that browsers use for the SPA, CORS, emails, and WebAuthn.

You can terminate TLS and route traffic with **any** reverse proxy: Nginx Proxy Manager, Caddy, Traefik, Cloudflare Tunnel, host nginx, etc. The Bun API only listens on a port (default **3001**); it does not embed a proxy.

## Paths to forward

| Path | Backend | Notes |
|------|---------|--------|
| `/` | SPA static files | SPA fallback → `index.html` |
| `/api/` | API `:3001` (or `services.giftistry.port`) | Raise body size for uploads (~300m) |
| `/ws/` | API | **WebSocket upgrade** required |
| `/docs` | API | OpenAPI UI |
| `/health` | API | Healthcheck |

Set `publicAppUrl` / `GIFTISTRY_PUBLIC_APP_URL` to the URL users type in the browser (e.g. `https://gifts.example.com`), not the raw API port.

## External proxy (recommended for production)

Typical pattern with **Nginx Proxy Manager** (or similar):

1. Run Giftistry API/worker only (`services.giftistry.web.enable = false` on NixOS, or Compose without relying on host nginx).
2. Proxy the host/path above to `http://<giftistry-host>:3001` for `/api/`, `/ws/`, `/docs`, `/health` (enable WebSockets for `/ws/`).
3. Serve the SPA on `/` (NPM custom locations, a static site, Docker `giftistry-web`, or built assets from `giftistry-web-bundle`).
4. Point `publicAppUrl` at the public HTTPS origin NPM exposes.

Firewall: open only what the proxy needs (usually 80/443 on the proxy host), not necessarily 3001 to the internet.

## Optional built-in nginx (NixOS)

When `services.giftistry.web.enable = true` (optional convenience, often for a laptop sandbox), the module:

- Builds the React SPA into a cache dir
- Enables **NixOS** `services.nginx` on `web.port` (default 3000) to serve that SPA and proxy API routes to `port` (3001)

That is **opt-in glue**, not required. For NPM / Traefik / Caddy in front of a homelab, prefer `web.enable = false` and wire the edge yourself.

The module still does **not** open firewall ports or configure ACME for you.

## Docker Compose

Publish `web` (default host port 8080; image already includes nginx + SPA + API proxy) and optionally terminate TLS on Traefik/Caddy/NPM in front:

```caddy
gifts.example.com {
  reverse_proxy 127.0.0.1:8080
}
```

Set `GIFTISTRY_PUBLIC_APP_URL=https://gifts.example.com`.

## NixOS host-owned nginx (example)

When not using `web.enable`, you can still run system nginx (or skip nginx entirely and use NPM elsewhere):

```nix
services.giftistry = {
  enable = true;
  publicAppUrl = "https://gifts.example.com";
  web.enable = false; # bring your own edge
};

services.nginx = {
  enable = true;
  virtualHosts."gifts.example.com" = {
    forceSSL = true;
    enableACME = true;
    root = "/var/cache/giftistry-web"; # or a giftistry-web-bundle path
    locations."/api/" = {
      proxyPass = "http://127.0.0.1:3001";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_read_timeout 300s;
        client_max_body_size 300m;
      '';
    };
    locations."/ws/" = {
      proxyPass = "http://127.0.0.1:3001";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_read_timeout 3600s;
      '';
    };
    locations."/docs".proxyPass = "http://127.0.0.1:3001";
    locations."/health".proxyPass = "http://127.0.0.1:3001";
    locations."/".tryFiles = "$uri $uri/ /index.html";
  };
};
```

Open ports yourself if needed (`networking.firewall.allowedTCPPorts = [ 80 443 ];`).

## CORS / cookies

The public URL must match what browsers use. Changing the domain without updating `publicAppUrl` / `GIFTISTRY_PUBLIC_APP_URL` breaks auth and WebAuthn.
