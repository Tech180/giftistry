{
  lib,
  stdenvNoCC,
  bun,
  giftistry-react,
}:
# Impure SPA build (needs network for `bun install`). Prefer Docker for CI/homelab.
stdenvNoCC.mkDerivation {
  pname = "giftistry-web-bundle";
  version = giftistry-react.rev or "dev";

  dontUnpack = true;

  nativeBuildInputs = [ bun ];

  # Requires: nix build .#giftistry-web-bundle --impure
  __noChroot = true;

  buildPhase = ''
    runHook preBuild
    cp -a ${giftistry-react} ./src
    chmod -R u+w ./src
    cd ./src
    bun install --frozen-lockfile
    export VITE_API_URL="''${VITE_API_URL:-}"
    bun run build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/giftistry-web
    cp -a ./src/build/. $out/share/giftistry-web/
    runHook postInstall
  '';

  meta = {
    description = "Giftistry web SPA (impure bun install)";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
