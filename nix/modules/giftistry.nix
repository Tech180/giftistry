# Giftistry NixOS module — systemd api + worker, optional local Postgres + SPA via nginx.
# When web.enable is true, nginx serves the SPA and proxies /api /ws /docs /health to the API.
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
    lib.optional (cfg.jwtSecretFile != null) "JWT_SECRET:${toString cfg.jwtSecretFile}"
    ++ lib.optional (cfg.database.passwordFile != null) "PGPASSWORD:${toString cfg.database.passwordFile}";

  commonEnv = {
    NODE_ENV = "production";
    GIFTISTRY_CONFIG_PATH = toString cfg.configFile;
    GIFTISTRY_PUBLIC_APP_URL = cfg.publicAppUrl;
    GIFTISTRY_STATE_DIR = toString cfg.stateDir;
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

  webRoot = cfg.web.root;

  # Sync API + theming into stateDir (flocked). Web SPA is a separate oneshot.
  prepareApp = pkgs.writeShellScript "giftistry-prepare-app" ''
    set -euo pipefail
    export PATH="${pkgs.bun}/bin:${pkgs.coreutils}/bin:${pkgs.findutils}/bin:${pkgs.gnused}/bin:${pkgs.util-linux}/bin:$PATH"
    export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
    mkdir -p "${cfg.stateDir}"
    stamp="${cfg.package}"
    marker="${cfg.stateDir}/.giftistry-package-stamp"
    lockfile="${cfg.stateDir}/.giftistry-prepare.lock"
    appdir="${cfg.stateDir}/app"

    exec 9>"$lockfile"
    flock 9

    if [ ! -f "$marker" ] || [ "$(cat "$marker")" != "$stamp" ]; then
      if [ -d "$appdir" ]; then
        chmod -R u+w "$appdir" || true
        rm -rf "$appdir"
      fi
      mkdir -p "$appdir"
      cp -a "${cfg.package}/lib/giftistry-bun/." "$appdir/"
      chmod -R u+w "$appdir"
      if [ -d "${cfg.package}/lib/theming-engine" ]; then
        if [ -d "${cfg.stateDir}/theming-engine" ]; then
          chmod -R u+w "${cfg.stateDir}/theming-engine" || true
          rm -rf "${cfg.stateDir}/theming-engine"
        fi
        cp -a "${cfg.package}/lib/theming-engine" "${cfg.stateDir}/theming-engine"
        chmod -R u+w "${cfg.stateDir}/theming-engine"
      fi
      cd "$appdir"
      bun install --frozen-lockfile --ignore-scripts || bun install --ignore-scripts
      if [ -d "${cfg.stateDir}/theming-engine" ]; then
        (cd "${cfg.stateDir}/theming-engine" && {
          bun install --frozen-lockfile --ignore-scripts || bun install --ignore-scripts
          bun run build
          test -f dist/js/theme-catalog.json
        })
      fi
      printf '%s\n' "$stamp" > "$marker"
      chown -R ${cfg.user}:${cfg.group} "$appdir" "$marker" || true
      if [ -d "${cfg.stateDir}/theming-engine" ]; then
        chown -R ${cfg.user}:${cfg.group} "${cfg.stateDir}/theming-engine" || true
      fi
    fi
  '';

  prepareWeb = pkgs.writeShellScript "giftistry-prepare-web" ''
    set -euo pipefail
    export PATH="${pkgs.bun}/bin:${pkgs.nodejs}/bin:${pkgs.coreutils}/bin:${pkgs.findutils}/bin:${pkgs.gnused}/bin:${pkgs.util-linux}/bin:$PATH"
    mkdir -p "${cfg.stateDir}"
    stamp="${cfg.package}"
    marker="${cfg.stateDir}/.giftistry-web-stamp"
    lockfile="${cfg.stateDir}/.giftistry-prepare.lock"
    webdir="${cfg.stateDir}/web"

    exec 9>"$lockfile"
    flock 9

    if [ ! -f "$marker" ] || [ "$(cat "$marker")" != "$stamp" ]; then
      if [ ! -d "${cfg.package}/lib/giftistry-react" ]; then
        echo "giftistry-prepare-web: package missing lib/giftistry-react" >&2
        exit 1
      fi
      if [ ! -f "${cfg.stateDir}/theming-engine/dist/js/theme-catalog.json" ]; then
        echo "giftistry-prepare-web: theming-engine not built yet (start giftistry-api first)" >&2
        exit 1
      fi
      if [ -d "$webdir" ]; then
        chmod -R u+w "$webdir" || true
        rm -rf "$webdir"
      fi
      mkdir -p "$webdir"
      cp -a "${cfg.package}/lib/giftistry-react/." "$webdir/"
      chmod -R u+w "$webdir"
      cd "$webdir"
      bun install --frozen-lockfile --ignore-scripts || bun install --ignore-scripts
      export VITE_API_URL=""
      # Avoid `bun run build` (runs tsc). Sync catalog then vite only.
      bun run scripts/sync-theme-catalog.ts
      # vite CLI lives in node_modules; its shebang needs node (on PATH above).
      ./node_modules/.bin/vite build
      mkdir -p "${webRoot}"
      find "${webRoot}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
      cp -a "$webdir/build/." "${webRoot}/"
      chmod -R a+rX "${webRoot}"
      printf '%s\n' "$stamp" > "$marker"
      chown -R ${cfg.user}:${cfg.group} "$webdir" "$marker" || true
    fi
  '';

  # NixOS proxyPass already sets proxy_http_version; only add headers / timeouts.
  nginxProxyHeaders = ''
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
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
        Giftistry package (API/worker/web sources under lib/, giftistry-db).
        Build with: nix build .#giftistry
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
      description = "API listen port (nginx proxies /api /ws /docs /health here when web.enable).";
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
      type = types.nullOr types.path;
      default = null;
      description = ''
        Optional file containing JWT_SECRET (systemd LoadCredential).
        When null, Bun auto-persists a secret at ''${stateDir}/jwt_secret
        (set GIFTISTRY_AUTO_JWT_SECRET=false to forbid). Prefer sops/jwtSecretFile for multi-host.
      '';
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

    web = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Build the React SPA at service start and serve it with nginx on web.port,
          proxying API routes to services.giftistry.port. Set publicAppUrl to the
          browser origin (e.g. http://127.0.0.1:3000).
        '';
      };

      port = mkOption {
        type = types.port;
        default = 3000;
        description = "nginx listen port for the SPA (+ API proxy).";
      };

      root = mkOption {
        type = types.path;
        default = "/var/cache/giftistry-web";
        description = "Directory nginx serves (populated by prepare from giftistry-react build/).";
      };
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
      {
        assertion = !cfg.web.enable || cfg.web.port != cfg.port;
        message = "services.giftistry.web.port must differ from services.giftistry.port.";
      }
    ];

    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.stateDir;
      createHome = true;
    };
    users.groups.${cfg.group} = { };

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

    # App persists settings via saveConfig() — giftistry must own the config path.
    systemd.tmpfiles.rules = [
      "d /etc/giftistry 0755 ${cfg.user} ${cfg.group} -"
      "z /etc/giftistry/config.json 0640 ${cfg.user} ${cfg.group} -"
    ]
    ++ lib.optionals cfg.web.enable [
      "d ${webRoot} 0755 root root -"
    ];

    systemd.services.giftistry-web-build = mkIf cfg.web.enable {
      description = "Build Giftistry SPA assets for nginx";
      after = [ "giftistry-api.service" ];
      requires = [ "giftistry-api.service" ];
      wantedBy = [ "multi-user.target" ];
      before = [ "nginx.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "+${prepareWeb}";
      };
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
        WorkingDirectory = cfg.stateDir;
        StateDirectory = "giftistry";
        StateDirectoryMode = "0755";
        ConfigurationDirectory = "giftistry";
        ConfigurationDirectoryMode = "0755";
        # Allow saving runtime settings (AllowSetup, SMTP, etc.) under /etc/giftistry.
        ReadWritePaths = [ "/etc/giftistry" ];
        ExecStartPre = [ "+${prepareApp}" ];
        ExecStart = pkgs.writeShellScript "giftistry-api-start" ''
          set -euo pipefail
          cd "${cfg.stateDir}/app"
          exec ${pkgs.bun}/bin/bun run --no-env-file src/index.ts
        '';
        Restart = "on-failure";
        RestartSec = "5s";
      }
      // lib.optionalAttrs (loadCredentials != [ ]) {
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
        WorkingDirectory = cfg.stateDir;
        StateDirectory = "giftistry";
        StateDirectoryMode = "0755";
        ConfigurationDirectory = "giftistry";
        ConfigurationDirectoryMode = "0755";
        ReadWritePaths = [ "/etc/giftistry" ];
        ExecStartPre = [ "+${prepareApp}" ];
        ExecStart = pkgs.writeShellScript "giftistry-worker-start" ''
          set -euo pipefail
          cd "${cfg.stateDir}/app"
          exec ${pkgs.bun}/bin/bun run --no-env-file src/worker.ts
        '';
        Restart = "on-failure";
        RestartSec = "5s";
      }
      // lib.optionalAttrs (loadCredentials != [ ]) {
        LoadCredential = loadCredentials;
      };
    };

    services.nginx = mkIf cfg.web.enable {
      enable = true;
      virtualHosts."giftistry" = {
        default = true;
        listen = [
          {
            addr = "0.0.0.0";
            port = cfg.web.port;
          }
          {
            addr = "[::]";
            port = cfg.web.port;
          }
        ];
        root = webRoot;
        locations = {
          "/api/" = {
            proxyPass = "http://127.0.0.1:${toString cfg.port}";
            extraConfig = nginxProxyHeaders + ''
              proxy_read_timeout 300s;
              client_max_body_size 300m;
            '';
          };
          "/ws/" = {
            proxyPass = "http://127.0.0.1:${toString cfg.port}";
            proxyWebsockets = true;
            extraConfig = nginxProxyHeaders + ''
              proxy_read_timeout 3600s;
            '';
          };
          "/docs" = {
            proxyPass = "http://127.0.0.1:${toString cfg.port}";
            extraConfig = nginxProxyHeaders;
          };
          "/health" = {
            proxyPass = "http://127.0.0.1:${toString cfg.port}";
            extraConfig = nginxProxyHeaders + ''
              access_log off;
            '';
          };
          "/" = {
            tryFiles = "$uri $uri/ /index.html";
          };
        };
      };
    };

    systemd.services.nginx = mkIf cfg.web.enable {
      after = [
        "giftistry-api.service"
        "giftistry-web-build.service"
      ];
      wants = [
        "giftistry-api.service"
        "giftistry-web-build.service"
      ];
    };
  };
}
