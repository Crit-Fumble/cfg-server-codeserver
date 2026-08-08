# syntax=docker/dockerfile:1.7
#
# cfg-server-codeserver — per-user hosted code-server (VS Code in
# the browser, coder/code-server, MIT) as a hosted tool-server kind (dt#204).
#
# The platform provisions ONE container per UserAppInstallation through the
# Server Manager kind registry (kinds/codeserver.ts → services/codeserver/
# launch.ts), CT-metered by active minute like every other kind. Alpha-gated
# (admin-only) at launch; Dev+ users later.
#
# Everything the user owns lives under /home/coder — the platform bind-mounts
# the installation's data dir there, so extensions, settings
# (~/.local/share/code-server), and checked-out repos survive container
# replacement. The image itself stays disposable.
#
# Auth: the platform derives a per-install password (HMAC over the core
# secret — never stored) and injects it as PASSWORD; code-server's own
# `--auth password` gate consumes it. The pin-cookie proxy in core-server is
# the outer wall — the container is never published to the internet directly.
#
# Build:
#   docker build -t cfg-server-codeserver:local .
#
# Run (local test):
#   docker run --rm -p 8080:8080 -e PASSWORD=dev -v /tmp/coder-home:/home/coder cfg-server-codeserver:local

ARG CODE_SERVER_VERSION=4.131.0

FROM codercom/code-server:${CODE_SERVER_VERSION}

ARG CODE_SERVER_VERSION

LABEL org.opencontainers.image.title="cfg-server-codeserver" \
      org.opencontainers.image.description="CodeBench — per-user code-server (VS Code in the browser) tool-server kind" \
      org.opencontainers.image.source="https://github.com/Crit-Fumble/cfg-server-codeserver" \
      org.opencontainers.image.licenses="AGPL-3.0-only" \
      org.opencontainers.image.version="${CODE_SERVER_VERSION}"

# ⚠️ `org.opencontainers.image.version` above does NOT survive to the published
# image: docker/metadata-action emits its own OCI label set and `--label`
# last-wins, so the release workflow overwrites it with the git tag (v0.1.0).
# Auditing "what upstream is in here?" via the OCI label therefore reads back
# OUR tag. The cfg.* namespace survives because the metadata action never emits
# it. Verified against the published :latest on 2026-08-08.
LABEL cfg.upstream.version="${CODE_SERVER_VERSION}"

# The upstream image runs as `coder` (uid 1000) with dumb-init as PID 1 and
# ships git + sudo. We only add curl (HEALTHCHECK) and our entrypoint.
USER root
RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/cfg-entrypoint.sh
RUN chmod +x /usr/local/bin/cfg-entrypoint.sh
USER coder

# code-server's own liveness endpoint — unauthenticated by design. The
# platform's status/proxy paths gate on docker health being `healthy`, so a
# real HEALTHCHECK here is load-bearing (port-bound alone is a wrong signal:
# code-server binds instantly, before the workbench can serve).
HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8080/healthz || exit 1

EXPOSE 8080/tcp

# Env knobs (set by core-server's launcher; defaults suit standalone runs):
#   PASSWORD              — code-server password auth (required; the launcher
#                           derives it per-install and never stores it)
#   CODESERVER_APP_NAME   — branding shown on the login page
ENV CODESERVER_APP_NAME="CFG code-server"

# dumb-init comes from the upstream image; our entrypoint execs code-server
# under it so SIGTERM lands cleanly on `docker stop`.
ENTRYPOINT ["/usr/bin/dumb-init", "--", "/usr/local/bin/cfg-entrypoint.sh"]
