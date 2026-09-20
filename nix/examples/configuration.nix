# Example — import into your own NixOS flake / configuration.nix.
# Giftistry does not manage nginx, firewall, or TLS.
#
#   giftistry.url = "path:/home/you/projects/giftistry/nix";
#   # or: url = "github:YOUR_ORG/giftistry?dir=nix";
#
#   nixpkgs.overlays = [ inputs.giftistry.overlays.default ];
#   imports = [ inputs.giftistry.nixosModules.giftistry ];
#
{
  pkgs,
  ...
}:
{
  services.giftistry = {
    enable = true;
    package = pkgs.giftistry; # API + worker + web assets + giftistry-db
    publicAppUrl = "https://gifts.example.com";
    jwtSecretFile = "/run/secrets/giftistry-jwt";
    port = 3001;

    database = {
      createLocal = true; # ensureDatabases / ensureUsers only
      name = "giftistry";
      user = "giftistry";
    };
  };

  # Your reverse proxy — example nginx (optional; use Caddy/Traefik the same way):
  #
  # services.nginx = {
  #   enable = true;
  #   virtualHosts."gifts.example.com" = {
  #     forceSSL = true;
  #     enableACME = true;
  #     root = "${pkgs.giftistry}/share/giftistry-web";
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
