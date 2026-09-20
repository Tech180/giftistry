{
  writeShellApplication,
  postgresql,
  schemaSql,
  migrateSql,
}:
# CLI for Giftistry Postgres helpers (sandbox SQL mirrors + ensure-db).
# Production schema upgrades still happen via the API (`runMigrations` on boot).
writeShellApplication {
  name = "giftistry-db";
  runtimeInputs = [ postgresql ];
  text = ''
    set -euo pipefail

    schema_sql="${schemaSql}"
    migrate_sql="${migrateSql}"

    usage() {
      cat <<'EOF'
    Usage: giftistry-db <command>

    Commands (honour PGHOST, PGPORT, PGUSER, PGPASSWORD, PGDATABASE):
      ensure        Create database $PGDATABASE if missing
      init-schema   Apply fresh-install schema.sql (sandbox / empty DB only)
      migrate       Apply migrate-existing.sql (additive sandbox upgrades)
      upgrade       Alias for migrate

    Production: prefer starting giftistry-api so Bun runMigrations() applies.
    These SQL files are mirrors for local/Nix sandboxes — see docs/schema.md.
    EOF
    }

    require_psql() {
      if ! command -v psql >/dev/null; then
        echo "giftistry-db: psql not found" >&2
        exit 1
      fi
      : "''${PGDATABASE:=giftistry}"
    }

    cmd_ensure() {
      require_psql
      local admin_db="''${PGADMIN_DATABASE:-postgres}"
      if psql -d "$admin_db" -tAc "SELECT 1 FROM pg_database WHERE datname = '$PGDATABASE'" | grep -q 1; then
        echo "database '$PGDATABASE' already exists"
        return 0
      fi
      echo "creating database '$PGDATABASE'..."
      createdb "$PGDATABASE"
    }

    cmd_init_schema() {
      require_psql
      echo "applying schema.sql to '$PGDATABASE'..."
      psql -d "$PGDATABASE" -v ON_ERROR_STOP=1 -f "$schema_sql"
    }

    cmd_migrate() {
      require_psql
      echo "applying migrate-existing.sql to '$PGDATABASE'..."
      psql -d "$PGDATABASE" -v ON_ERROR_STOP=1 -f "$migrate_sql"
    }

    case "''${1:-}" in
      ensure) cmd_ensure ;;
      init-schema) cmd_init_schema ;;
      migrate | upgrade) cmd_migrate ;;
      -h | --help | help | "") usage ;;
      *)
        echo "giftistry-db: unknown command: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
  '';
}
