# Giftistry API — multi-stage Bun image (giftistry-server)
#
# Build context must be the parent directory that contains:
#   giftistry-bun/, theming-engine/, (optional) giftistry-react/
#
# Secrets (pick one approach):
#   JWT_SECRET              — inline env (compose / k8s)
#   JWT_SECRET_FILE         — path to a file containing the secret
#   CREDENTIALS_DIRECTORY   — directory of files named JWT_SECRET, SMTP_PASS, etc.
#   GIFTISTRY_CREDENTIALS_DIRECTORY — alias for CREDENTIALS_DIRECTORY
#
# Config:
#   GIFTISTRY_CONFIG_PATH   — path to config.json (SMTP, AI, OAuth settings)
#
# Image includes Playwright Chromium for scraping (~large). Prefer GHCR pulls for operators.

ARG GIFTISTRY_VERSION=dev
ARG GIFTISTRY_SOURCE=https://github.com/Tech180/giftistry

FROM oven/bun:1.2-debian AS deps
WORKDIR /app
COPY giftistry-bun/package.json giftistry-bun/bun.lock* ./
RUN bun install --frozen-lockfile || bun install

FROM oven/bun:1.2-debian AS theming
WORKDIR /theming-engine
COPY theming-engine/package.json theming-engine/bun.lock* ./
RUN bun install --frozen-lockfile || bun install
COPY theming-engine/ ./
RUN bun run build
RUN test -f dist/js/theme-catalog.json \
  || (echo "theming-engine build missing dist/js/theme-catalog.json — need theming-engine >= 0.0.4 (commit 2e74db3+). On the host: cd theming-engine && git pull && docker compose build --no-cache" >&2; exit 1)

FROM oven/bun:1.2-debian AS app
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY giftistry-bun/ ./
COPY --from=theming /theming-engine /theming-engine
ENV PLAYWRIGHT_BROWSERS_PATH=/app/.playwright
# Browser binary only. OS libraries are installed in the runtime stage;
# apt packages from this stage are not copied forward.
RUN bunx playwright install chromium

FROM oven/bun:1.2-debian AS runtime
ARG GIFTISTRY_VERSION=dev
ARG GIFTISTRY_SOURCE=https://github.com/Tech180/giftistry
LABEL org.opencontainers.image.title="Giftistry server" \
  org.opencontainers.image.description="Giftistry API and background worker" \
  org.opencontainers.image.source="${GIFTISTRY_SOURCE}" \
  org.opencontainers.image.version="${GIFTISTRY_VERSION}" \
  org.opencontainers.image.licenses="SEE LICENSE IN LICENSE"

WORKDIR /app
ENV NODE_ENV=production \
    PORT=3001 \
    PLAYWRIGHT_BROWSERS_PATH=/app/.playwright

RUN groupadd -r giftistry && useradd -r -g giftistry -d /app giftistry

COPY --from=app --chown=giftistry:giftistry /app /app
COPY --from=app --chown=giftistry:giftistry /theming-engine /theming-engine
COPY giftistry/docker/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod 755 /usr/local/bin/docker-entrypoint.sh \
  && mkdir -p /etc/giftistry /var/lib/giftistry \
  && chown giftistry:giftistry /etc/giftistry /var/lib/giftistry

# Playwright's Chromium needs host libs (libglib-2.0, nss, etc.). The
# browser under /app/.playwright is copied from the app stage; those
# shared libraries are not, so install them here.
RUN DEBIAN_FRONTEND=noninteractive bunx playwright install-deps chromium \
  && rm -rf /var/lib/apt/lists/*

# Entrypoint runs as root to chown bind mounts, then drops to giftistry.
USER root
EXPOSE 3001

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD bun -e "fetch('http://127.0.0.1:' + (process.env.PORT || 3001) + '/health').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["bun", "run", "--no-env-file", "src/index.ts"]
