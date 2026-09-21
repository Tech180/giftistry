# Example — import into your own NixOS flake / configuration.nix.
#
#   giftistry.url = "path:/home/you/projects/giftistry/nix";
#   # or: url = "github:YOUR_ORG/giftistry?dir=nix";
#
#   nixpkgs.overlays = [ inputs.giftistry.overlays.default ];
#   imports = [ inputs.giftistry.nixosModules.giftistry ];
#
# Edge / TLS / firewall: prefer an external reverse proxy (Nginx Proxy Manager,
# Caddy, Traefik, …). See docs/reverse-proxy.md.
# Optional: services.giftistry.web.enable = true for local SPA + NixOS nginx.
#
{
  pkgs,
  ...
}:
{
  services.giftistry = {
    enable = true;
    package = pkgs.giftistry; # API + worker + web sources + giftistry-db
    publicAppUrl = "https://gifts.example.com"; # browser-facing origin
    web.enable = false; # production: bring your own edge (NPM, etc.)
    # Optional — omit to let Bun auto-persist JWT under stateDir/jwt_secret
    # jwtSecretFile = "/run/secrets/giftistry-jwt";
    port = 3001;

    database = {
      createLocal = true; # ensureDatabases / ensureUsers only
      name = "giftistry";
      user = "giftistry";
    };
  };

  # Your reverse proxy — example host nginx (optional; NPM/Caddy/Traefik the same idea):
  #
  # services.nginx = {
  #   enable = true;
  #   virtualHosts."gifts.example.com" = {
  #     forceSSL = true;
  #     enableACME = true;
  #     root = "/var/cache/giftistry-web";
  #     locations."/api/".proxyPass = "http://127.0.0.1:3001";
  #     locations."/ws/" = {
  #       proxyPass = "http://127.0.0.1:3001";
  #       proxyWebsockets = true;
  #     };
  #     locations."/docs".proxyPass = "http://127.0.0.1:3001";
  #     locations."/health".proxyPass = "http://127.0.0.1:3001";
  #     locations."/".tryFiles = "$uri $uri/ /index.html";
  #   };
  # };
  #
  # Sandbox / manual SQL (not production migrate path):
  #   giftistry-db ensure
  #   giftistry-db migrate   # or: giftistry-db upgrade
}
