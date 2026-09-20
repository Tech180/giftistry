# Reverse proxy

Giftistry expects a single public origin (`GIFTISTRY_PUBLIC_APP_URL` / `services.giftistry.publicAppUrl`) that serves the SPA and proxies API + WebSocket traffic.

The NixOS module does **not** enable nginx or open firewall ports. Wire the edge in your host config.

## Paths to forward

| Path | Backend | Notes |
|------|---------|--------|
| `/` | SPA static files | `try_files` → `index.html` |
| `/api/` | API `:3001` (or `services.giftistry.port`) | Raise body size for uploads (~300m) |
| `/ws/` | API | **WebSocket upgrade** required |
| `/docs` | API | OpenAPI UI |
| `/health` | API | Healthcheck |

SPA root on Nix: `${pkgs.giftistry}/share/giftistry-web`.

## Docker Compose

Publish `web` (default host port 8080) and terminate TLS on Traefik/Caddy/nginx:

```caddy
gifts.example.com {
  reverse_proxy 127.0.0.1:8080
}
```

Set `GIFTISTRY_PUBLIC_APP_URL=https://gifts.example.com`.

## NixOS nginx (host-owned)

```nix
services.nginx = {
  enable = true;
  virtualHosts."gifts.example.com" = {
    forceSSL = true;
    enableACME = true;
    root = "${pkgs.giftistry}/share/giftistry-web";
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
