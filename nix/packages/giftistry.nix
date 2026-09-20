{
  lib,
  stdenvNoCC,
  giftistry-api,
  giftistry-web,
  giftistry-db,
}:
# Umbrella package: API/worker sources + web assets + giftistry-db CLI.
# Import via overlay as pkgs.giftistry, or: nix build .#giftistry
stdenvNoCC.mkDerivation {
  pname = "giftistry";
  version = giftistry-api.version or "dev";

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/lib $out/share
    cp -a ${giftistry-api}/lib/. $out/lib/
    cp -a ${giftistry-api}/bin/. $out/bin/
    chmod -R u+w $out/bin $out/lib
    mkdir -p $out/share
    cp -a ${giftistry-web}/share/giftistry-web $out/share/giftistry-web
    cp -a ${giftistry-db}/bin/giftistry-db $out/bin/giftistry-db
    runHook postInstall
  '';

  passthru = {
    inherit giftistry-api giftistry-web giftistry-db;
    webRoot = "${giftistry-web}/share/giftistry-web";
  };

  meta = {
    description = "Giftistry (API, worker, web assets, giftistry-db)";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "giftistry-api";
  };
}
