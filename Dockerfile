# syntax=docker/dockerfile:1.7
# Pi Web for Railway.
# Upstream publishes no prebuilt image: its own docker/Dockerfile builds an
# Ubuntu 26.04 image from the npm packages. This file follows that build at a
# pinned release (Pi Web 1.202611.5 + Pi Coding Agent 1.6.0), without the Docker
# CLI and Playwright browser libraries (no Docker socket on Railway), and adds a
# Caddy front with HTTP basic auth (generated password) and an open /healthz.
# Bump the pins together with a CHANGELOG.md entry: a merge to main notifies deployers.

FROM caddy:2.11.9-alpine@sha256:003a97808e781aa9f7e75cc2f43d34d461099031faf5e20faefb9f61126836f0 AS caddy
FROM node:22.22.2-bookworm-slim@sha256:9f6d5975c7dca860947d3915877f85607946403fc55349f39b4bc3688448bb6e AS node-runtime
FROM ubuntu:26.04@sha256:d66b366dac61b575bee2aef07e9c26e8070096fbe84a3d4d3eb0da069b5d76db AS base

ARG MISE_VERSION=2026.10.17
ARG PI_WEB_UID=1000
ARG PI_WEB_GID=1000
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV NPM_CONFIG_UPDATE_NOTIFIER=false \
    NPM_CONFIG_PREFIX=/usr/local \
    LANG=C.UTF-8 \
    SHELL=/bin/bash \
    TERM=xterm-256color

# Upstream layout: the image-owned Node runtime lives outside the volume.
COPY --from=node-runtime /usr/local/ /usr/local/lib/pi-web-node/
RUN ln -s /usr/local/lib/pi-web-node/bin/node /usr/local/bin/node \
 && ln -s /usr/local/lib/pi-web-node/bin/npm /usr/local/bin/npm \
 && ln -s /usr/local/lib/pi-web-node/bin/npx /usr/local/bin/npx
# Upstream's base installer (unchanged copy from docker/internal/image at v1.202611.5):
# git, build tools, python3, ripgrep, jq, mise + gh, and the pi-web user (uid 1000).
COPY --chmod=0755 docker/install-ubuntu-base /usr/local/sbin/install-pi-web-ubuntu-base
RUN install-pi-web-ubuntu-base

FROM base AS package
ARG PI_WEB_VERSION=1.202611.5
ARG PI_CODING_AGENT_VERSION=1.6.0
RUN npm install -g --omit=dev --no-audit --no-fund \
      "@earendil-works/pi-coding-agent@${PI_CODING_AGENT_VERSION}" \
      "@jmfederico/pi-web@${PI_WEB_VERSION}" --allow-scripts=node-pty \
 && command -v pi \
 && npm cache clean --force

FROM base AS runtime
ENV NPM_CONFIG_PREFIX="" \
    HOME=/data/home \
    XDG_CONFIG_HOME=/data/config \
    MISE_CONFIG_DIR=/data/config/mise \
    MISE_DATA_DIR=/data/home/.local/share/mise \
    MISE_SHARED_INSTALL_DIRS=/usr/local/share/pi-web/mise/installs \
    MISE_CACHE_DIR=/data/home/.cache/mise \
    MISE_STATE_DIR=/data/home/.local/state/mise \
    MISE_AUTO_INSTALL=false \
    MISE_NOT_FOUND_SYSTEM_FALLBACK=false \
    MISE_PARANOID=true \
    MISE_YES=false \
    PI_WEB_HOST=127.0.0.1 \
    PI_WEB_PORT=8504 \
    PI_WEB_DATA_DIR=/data/pi-web \
    PI_WEB_SESSIOND_SOCKET=/data/pi-web/sessiond.sock \
    PI_CODING_AGENT_DIR=/data/pi-agent \
    PI_WEB_SKIP_VERSION_CHECK=1 \
    PI_TELEMETRY=0 \
    PORT=8080
ENV PATH=/data/home/.local/share/mise/shims:/usr/local/share/pi-web/mise/shims:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

COPY --from=package /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=package /usr/local/bin /usr/local/bin
COPY --from=caddy /usr/bin/caddy /usr/local/bin/caddy
COPY --chmod=0755 docker/pi-web-service /usr/local/bin/pi-web-service
COPY --chmod=0755 start.sh /usr/local/bin/pi-web-railway-start
COPY Caddyfile /etc/pi-web-railway/Caddyfile
COPY gitconfig /etc/gitconfig

WORKDIR /data/workspace
EXPOSE 8080
# The start script runs as root only to prepare the /data volume, then starts
# every process as the unprivileged pi-web user.
ENTRYPOINT ["tini", "--", "/usr/local/bin/pi-web-railway-start"]
