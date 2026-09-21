{
  description = "Giftistry packaging flake — packages + NixOS module + local Postgres sandbox";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # App sources as git+file so untracked PG sockets / node_modules are not copied.
    # Override with github:… when publishing, or --override-input for CI stubs.
    giftistry-bun = {
      url = "git+file:///home/tech180/Documents/projects/giftistry-bun";
      flake = false;
    };
    giftistry-react = {
      url = "git+file:///home/tech180/Documents/projects/giftistry-react";
      flake = false;
    };
    theming-engine = {
      url = "git+file:///home/tech180/Documents/projects/theming-engine";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      giftistry-bun,
      giftistry-react,
      theming-engine,
    }:
    let
      nixosModule = ./modules/giftistry.nix;

      overlay =
        final: _prev:
        let
          giftistry-api = final.callPackage ./packages/api.nix {
            inherit giftistry-bun giftistry-react theming-engine;
          };
          giftistry-web = final.callPackage ./packages/web.nix {
            inherit giftistry-react;
          };
          giftistry-web-bundle = final.callPackage ./packages/web-bundle.nix {
            inherit giftistry-react;
          };
          giftistry-db = final.callPackage ./packages/db.nix {
            schemaSql = ./sql/schema.sql;
            migrateSql = ./sql/migrate-existing.sql;
          };
          giftistry = final.callPackage ./packages/giftistry.nix {
            inherit giftistry-api giftistry-web giftistry-db;
          };
        in
        {
          inherit
            giftistry
            giftistry-api
            giftistry-web
            giftistry-web-bundle
            giftistry-db
            ;
        };
    in
    {
      overlays.default = overlay;

      nixosModules.giftistry = nixosModule;
      nixosModules.default = nixosModule;
    }
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [ overlay ];
        };

        postgresql = pkgs.postgresql_18;
        pgMajor = pkgs.lib.versions.major postgresql.version;

        schemaSql = ./sql/schema.sql;
        migrateSql = ./sql/migrate-existing.sql;

        inherit (pkgs)
          giftistry
          giftistry-api
          giftistry-web
          giftistry-web-bundle
          giftistry-db
          ;

        moduleEval = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            nixosModule
            {
              services.giftistry = {
                enable = true;
                publicAppUrl = "https://gifts.example.com";
                package = giftistry;
                database.createLocal = false;
              };
              boot.loader.grub.enable = false;
              fileSystems."/" = {
                device = "none";
                fsType = "tmpfs";
              };
              system.stateVersion = "25.05";
              nixpkgs.pkgs = pkgs;
            }
          ];
        };
      in
      {
        packages = {
          inherit
            giftistry
            giftistry-api
            giftistry-web
            giftistry-web-bundle
            giftistry-db
            ;
          default = giftistry;
        };

        checks = {
          giftistry = giftistry;
          giftistry-db = giftistry-db;
          nixos-module = pkgs.writeText "giftistry-nixos-module-check" ''
            ExecStart=${moduleEval.config.systemd.services.giftistry-api.serviceConfig.ExecStart}
            worker=${
              if moduleEval.config.systemd.services ? giftistry-worker then "yes" else "no"
            }
            hasNginx=${
              if moduleEval.config.services.nginx.enable or false then "yes" else "no"
            }
          '';
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            bun
            postgresql
            nodejs
            python3
            mailpit
            chromium
            giftistry-db
          ];

          shellHook = ''
            export SCRAPE_PLAYWRIGHT_EXECUTABLE_PATH="${pkgs.chromium}/bin/chromium"
            export GIFTISTRY_PUBLIC_APP_URL="http://localhost:3000"
            export NODE_ENV="development"
            # Non-production JWT default; override JWT_SECRET for shared environments.
            export JWT_SECRET="''${JWT_SECRET:-local_secret_key_for_giftistry}"

            # Check if current directory is writable, default to user's home if not
            if [ -w "$PWD" ]; then
              export PGDATA="$PWD/.local/postgres"
            else
              export PGDATA="$HOME/.local/share/giftistry/postgres"
            fi
            export PGHOST="$PGDATA"
            export PGUSER="postgres"
            export PGPASSWORD=""
            export PGDATABASE="giftistry"

            apply_giftistry_migrations() {
              if pg_isready -h "$PGDATA" -q 2>/dev/null; then
                giftistry-db migrate >/dev/null
              fi
            }

            ensure_giftistry_test_database() {
              if pg_isready -h "$PGDATA" -q 2>/dev/null; then
                if ! psql -h "$PGDATA" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = 'giftistry_test'" | grep -q 1; then
                  echo "Creating giftistry_test database..."
                  createdb -h "$PGDATA" giftistry_test
                fi
              fi
            }

            init_giftistry_database() {
              echo "Initializing local PostgreSQL ${pgMajor} database for Giftistry..."
              mkdir -p "$(dirname "$PGDATA")"
              initdb -U postgres --auth=trust >/dev/null

              echo "Starting database temporarily to apply schema..."
              pg_ctl start -l "$PGDATA/server.log" -o "-k $PGDATA" >/dev/null

              while ! pg_isready -h "$PGDATA" -q; do
                sleep 1
              done

              echo "Creating 'giftistry' database..."
              createdb -h "$PGDATA" giftistry

              echo "Injecting table schema..."
              giftistry-db init-schema

              echo "Stopping temporary database..."
              pg_ctl stop -m fast >/dev/null
              echo "Database initialized and seeded."
            }

            # Major-version upgrades can't reuse PGDATA; back it up and re-init.
            if [ -d "$PGDATA" ] && [ -f "$PGDATA/PG_VERSION" ]; then
              existing_major="$(tr -d '[:space:]' < "$PGDATA/PG_VERSION")"
              if [ "$existing_major" != "${pgMajor}" ]; then
                backup_dir="''${PGDATA}.backup-pg''${existing_major}-$(date +%Y%m%d-%H%m%S)"
                echo "PostgreSQL major mismatch: data is $existing_major, shell provides ${pgMajor}."
                echo "Moving old data to: $backup_dir"
                mv "$PGDATA" "$backup_dir"
              fi
            fi

            if [ ! -d "$PGDATA" ]; then
              init_giftistry_database
            fi

            echo ""
            echo "================================================="
            echo "Giftistry Local Sandbox Active"
            echo "================================================="
            echo "PostgreSQL: ${postgresql.version}"
            echo "App URL   : $GIFTISTRY_PUBLIC_APP_URL"
            echo "JWT_SECRET: set (dev default if unset)"
            echo "Database  : pg_ctl start -l \$PGDATA/server.log -o \"-k \$PGDATA\""
            echo "Stop DB   : pg_ctl stop"
            echo "DB CLI    : giftistry-db ensure|init-schema|migrate|upgrade"
            echo "SQL mirrors: nix/sql/ (sandbox only — production uses Bun runMigrations)"
            echo "================================================="
            echo ""

            if [ -d "$PGDATA" ] && [ -f "$PGDATA/PG_VERSION" ]; then
              if pg_isready -h "$PGDATA" -q 2>/dev/null; then
                apply_giftistry_migrations && echo "Applied Giftistry schema migrations."
                ensure_giftistry_test_database
              fi
            fi
          '';
        };
      }
    );
}
