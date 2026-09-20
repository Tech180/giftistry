# Giftistry NixOS module — systemd api + worker, optional local Postgres.
# Does not manage nginx, firewall, or TLS: wire those in your host config.
# Point a reverse proxy at the API port and ${package}/share/giftistry-web.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.giftistry;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  loadCredentials =
    [ "JWT_SECRET:${toString cfg.jwtSecretFile}" ]
    ++ lib.optional (cfg.database.passwordFile != null) "PGPASSWORD:${toString cfg.database.passwordFile}";

  commonEnv = {
    NODE_ENV = "production";
    GIFTISTRY_CONFIG_PATH = toString cfg.configFile;
    GIFTISTRY_PUBLIC_APP_URL = cfg.publicAppUrl;
    PGHOST = if cfg.database.createLocal then "/run/postgresql" else cfg.database.host;
    PGPORT = toString cfg.database.port;
    PGUSER = cfg.database.user;
    PGDATABASE = cfg.database.name;
    SCRAPE_PLAYWRIGHT_EXECUTABLE_PATH = "${pkgs.chromium}/bin/chromium";
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
  }
  // lib.optionalAttrs (cfg.credentialsDirectory != null) {
    GIFTISTRY_CREDENTIALS_DIRECTORY = toString cfg.credentialsDirectory;
  }
  // cfg.environment;

  # Sync store sources into stateDir and install Bun deps once per package stamp.
  prepareApp = pkgs.writeShellScript "giftistry-prepare-app" ''
    set -euo pipefail
    stamp="${cfg.package}"
    marker="${cfg.stateDir}/.giftistry-package-stamp"
    appdir="${cfg.stateDir}/app"
    if [ ! -f "$marker" ] || [ "$(cat "$marker")" != "$stamp" ]; then
      rm -rf "$appdir"
      mkdir -p "$appdir"
      cp -a "${cfg.package}/lib/giftistry-bun/." "$appdir/"
      if [ -d "${cfg.package}/lib/theming-engine" ]; then
        rm -rf "${cfg.stateDir}/theming-engine"
        cp -a "${cfg.package}/lib/theming-engine" "${cfg.stateDir}/theming-engine"
      fi
      cd "$appdir"
      export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
      ${pkgs.bun}/bin/bun install --frozen-lockfile
      if [ -d "${cfg.stateDir}/theming-engine" ]; then
        (cd "${cfg.stateDir}/theming-engine" && ${pkgs.bun}/bin/bun install --frozen-lockfile && ${pkgs.bun}/bin/bun run build) || true
      fi
      printf '%s\n' "$stamp" > "$marker"
      chown -R ${cfg.user}:${cfg.group} "$appdir" "$marker" || true
      if [ -d "${cfg.stateDir}/theming-engine" ]; then
        chown -R ${cfg.user}:${cfg.group} "${cfg.stateDir}/theming-engine" || true
      fi
    fi
  '';
in
{
  options.services.giftistry = {
    enable = mkEnableOption "Giftistry API and worker (bundle front/back via package)";

    enableWorker = mkOption {
      type = types.bool;
      default = true;
      description = "Run a separate giftistry-worker systemd service.";
    };

    package = mkOption {
      type = types.package;
      default =
        if pkgs ? giftistry then
          pkgs.giftistry
        else
          throw ''
            services.giftistry.package is unset and pkgs.giftistry is missing.
            Add inputs.giftistry.overlays.default to nixpkgs.overlays, or set package explicitly.
          '';
      defaultText = lib.literalExpression "pkgs.giftistry";
      description = ''
        Giftistry package (API/worker sources, web assets under share/giftistry-web,
        and giftistry-db). Build with: nix build .#giftistry
      '';
    };

    publicAppUrl = mkOption {
      type = types.str;
      description = "Public browser origin (CORS, emails, WebAuthn). Required when enable.";
      example = "https://gifts.example.com";
    };

    port = mkOption {
      type = types.port;
      default = 3001;
      description = "API listen port (proxy /api /ws /docs /health here).";
    };

    configFile = mkOption {
      type = types.path;
      default = "/etc/giftistry/config.json";
      description = "Path to Giftistry config.json (GIFTISTRY_CONFIG_PATH).";
    };

    stateDir = mkOption {
      type = types.path;
      default = "/var/lib/giftistry";
      description = "Persistent application state directory.";
    };

    user = mkOption {
      type = types.str;
      default = "giftistry";
      description = "System user for Giftistry services.";
    };

    group = mkOption {
      type = types.str;
      default = "giftistry";
      description = "System group for Giftistry services.";
    };

    jwtSecretFile = mkOption {
      type = types.path;
      description = "File containing JWT_SECRET. Exposed via systemd LoadCredential as JWT_SECRET.";
    };

    credentialsDirectory = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Optional extra credentials directory (GIFTISTRY_CREDENTIALS_DIRECTORY). systemd LoadCredential also sets CREDENTIALS_DIRECTORY.";
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Extra environment variables merged into api and worker units.";
    };

    database = {
      createLocal = mkOption {
        type = types.bool;
        default = true;
        description = "Provision a local PostgreSQL database via services.postgresql (DB + role only).";
      };

      name = mkOption {
        type = types.str;
        default = "giftistry";
        description = "Database name.";
      };

      user = mkOption {
        type = types.str;
        default = "giftistry";
        description = "Database role.";
      };

      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Database host when createLocal is false.";
      };

      port = mkOption {
        type = types.port;
        default = 5432;
        description = "Database port.";
      };

      passwordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Optional PGPASSWORD file (LoadCredential). Usually unset for local peer auth.";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.publicAppUrl != "";
        message = "services.giftistry.publicAppUrl must be set.";
      }
    ];

    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.stateDir;
      createHome = true;
    };
    users.groups.${cfg.group} = { };

    # Expose giftistry-api / giftistry-worker / giftistry-db on PATH.
    environment.systemPackages = [ cfg.package ];

    services.postgresql = mkIf cfg.database.createLocal {
      enable = true;
      ensureDatabases = [ cfg.database.name ];
      ensureUsers = [
        {
          name = cfg.database.user;
          ensureDBOwnership = true;
        }
      ];
    };

    systemd.services.giftistry-api = {
      description = "Giftistry API";
      after = [ "network-online.target" ] ++ lib.optionals cfg.database.createLocal [ "postgresql.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      environment = commonEnv // {
        PORT = toString cfg.port;
        GIFTISTRY_PROCESS_ROLE = "api";
      };
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = "${cfg.stateDir}/app";
        StateDirectory = "giftistry";
        ConfigurationDirectory = "giftistry";
        ExecStartPre = [ "+${prepareApp}" ];
        ExecStart = "${pkgs.bun}/bin/bun run --no-env-file src/index.ts";
        Restart = "on-failure";
        RestartSec = "5s";
        LoadCredential = loadCredentials;
      };
    };

    systemd.services.giftistry-worker = mkIf cfg.enableWorker {
      description = "Giftistry background job worker";
      after = [
        "network-online.target"
        "giftistry-api.service"
      ]
      ++ lib.optionals cfg.database.createLocal [ "postgresql.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      environment = commonEnv // {
        GIFTISTRY_PROCESS_ROLE = "worker";
      };
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = "${cfg.stateDir}/app";
        StateDirectory = "giftistry";
        ConfigurationDirectory = "giftistry";
        ExecStartPre = [ "+${prepareApp}" ];
        ExecStart = "${pkgs.bun}/bin/bun run --no-env-file src/worker.ts";
        Restart = "on-failure";
        RestartSec = "5s";
        LoadCredential = loadCredentials;
      };
    };
  };
}
