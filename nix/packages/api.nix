{
  lib,
  stdenvNoCC,
  bun,
  makeWrapper,
  giftistry-bun,
  theming-engine,
}:
stdenvNoCC.mkDerivation {
  pname = "giftistry-api";
  version = giftistry-bun.rev or "dev";

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib $out/bin
    cp -a ${giftistry-bun} $out/lib/giftistry-bun
    chmod -R u+w $out/lib/giftistry-bun
    cp -a ${theming-engine} $out/lib/theming-engine
    chmod -R u+w $out/lib/theming-engine

    # Wrappers for convenience (NixOS module prefers bun + stateDir app copy).
    makeWrapper ${bun}/bin/bun $out/bin/giftistry-api \
      --prefix PATH : ${lib.makeBinPath [ bun ]} \
      --set PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD 1 \
      --add-flags "run --no-env-file src/index.ts"

    makeWrapper ${bun}/bin/bun $out/bin/giftistry-worker \
      --prefix PATH : ${lib.makeBinPath [ bun ]} \
      --set PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD 1 \
      --set GIFTISTRY_PROCESS_ROLE worker \
      --add-flags "run --no-env-file src/worker.ts"

    runHook postInstall
  '';

  meta = {
    description = "Giftistry API and worker sources (Bun deps installed at service start)";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
