# Giftistry web — Vite build + nginx (SPA + API/WebSocket proxy)
#
# Build context: parent directory containing giftistry/, giftistry-react/, theming-engine/

ARG GIFTISTRY_VERSION=dev
ARG GIFTISTRY_SOURCE=https://github.com/Tech180/giftistry

# Theme catalog sync (prebuild) reads ../theming-engine/dist/js/theme-catalog.json
FROM oven/bun:1.2-debian AS theming
WORKDIR /theming-engine
COPY theming-engine/package.json theming-engine/bun.lock* ./
RUN bun install --frozen-lockfile || bun install
COPY theming-engine/ ./
RUN bun run build

FROM oven/bun:1.2-debian AS build
WORKDIR /web
COPY giftistry-react/package.json giftistry-react/bun.lock* ./
RUN bun install --frozen-lockfile || bun install
COPY giftistry-react/ ./
COPY --from=theming /theming-engine /theming-engine
ARG VITE_API_URL=
ENV VITE_API_URL=${VITE_API_URL}
RUN bun run build

FROM nginx:1.27-alpine AS runtime
ARG GIFTISTRY_VERSION=dev
ARG GIFTISTRY_SOURCE=https://github.com/Tech180/giftistry
LABEL org.opencontainers.image.title="Giftistry web" \
  org.opencontainers.image.description="Giftistry SPA served by nginx" \
  org.opencontainers.image.source="${GIFTISTRY_SOURCE}" \
  org.opencontainers.image.version="${GIFTISTRY_VERSION}" \
  org.opencontainers.image.licenses="SEE LICENSE IN LICENSE"

COPY giftistry/docker/nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --from=build /web/build /usr/share/nginx/html
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget -qO- http://127.0.0.1/ >/dev/null || exit 1
