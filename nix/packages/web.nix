{
  lib,
  stdenvNoCC,
  giftistry-react,
}:
# Placeholder SPA root so the NixOS module and `nix flake check` stay pure.
# For a real build, use Docker Compose (`giftistry/docker`) or:
#   nix build .#giftistry-web-bundle --impure
# and set services.giftistry.webPackage to that result.
stdenvNoCC.mkDerivation {
  pname = "giftistry-web";
  version = giftistry-react.rev or "dev";

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/giftistry-web
    cat > $out/share/giftistry-web/index.html <<'EOF'
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Giftistry</title>
  </head>
  <body>
    <main style="font-family: system-ui; max-width: 40rem; margin: 3rem auto; padding: 0 1rem;">
      <h1>Giftistry</h1>
      <p>
        Web assets are not bundled in this pure Nix package. Build the SPA with
        Docker Compose or <code>nix build .#giftistry-web-bundle --impure</code>,
        then set <code>services.giftistry.webPackage</code>.
      </p>
      <p>API health (when proxied): <a href="/health">/health</a></p>
    </main>
  </body>
</html>
EOF
    runHook postInstall
  '';

  meta = {
    description = "Giftistry web placeholder (pure); use giftistry-web-bundle for a real SPA build";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
