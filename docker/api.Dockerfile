# Giftistry API — multi-stage Bun image
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

FROM oven/bun:1.2-debian AS deps
WORKDIR /app
COPY giftistry-bun/package.json giftistry-bun/bun.lock ./
RUN bun install --frozen-lockfile

FROM oven/bun:1.2-debian AS theming
WORKDIR /theming-engine
COPY theming-engine/package.json theming-engine/bun.lock* ./
RUN bun install --frozen-lockfile || bun install
COPY theming-engine/ ./
RUN bun run build

FROM oven/bun:1.2-debian AS app
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY giftistry-bun/ ./
COPY --from=theming /theming-engine /theming-engine
ENV PLAYWRIGHT_BROWSERS_PATH=/app/.playwright
RUN bunx playwright install chromium --with-deps

FROM oven/bun:1.2-debian AS runtime
WORKDIR /app
ENV NODE_ENV=production \
    PORT=3001 \
    PLAYWRIGHT_BROWSERS_PATH=/app/.playwright

RUN groupadd -r giftistry && useradd -r -g giftistry -d /app giftistry

COPY --from=app --chown=giftistry:giftistry /app /app
COPY --from=app --chown=giftistry:giftistry /theming-engine /theming-engine

USER giftistry
EXPOSE 3001

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD bun -e "fetch('http://127.0.0.1:' + (process.env.PORT || 3001) + '/health').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"

CMD ["bun", "run", "--no-env-file", "src/index.ts"]
