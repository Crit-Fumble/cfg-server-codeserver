# syntax=docker/dockerfile:1.7
#
# cfg-server-codeserver — per-user hosted code-server (VS Code in
# the browser, coder/code-server, MIT) as a hosted tool-server kind (dt#204).
#
# The platform provisions ONE container per UserAppInstallation through the
# Server Manager kind registry (kinds/codeserver.ts → services/codeserver/
# launch.ts), CT-metered like every other kind: per 10-minute interval while
# it runs, plus a final remainder at stop. Alpha-gated (admin-only) at launch;
# Dev+ users later.
#
# Everything the user owns lives under /home/coder — the platform bind-mounts
# the installation's data dir there, so extensions, settings
# (~/.local/share/code-server), and checked-out repos survive container
# replacement. The image itself stays disposable.
#
# The box is for developing the CFG repos, so it ships what they need on top
# of upstream: Node 24 (the repos' engines floor), the GitHub CLI (the user's
# own `gh auth login` is how git and GitHub Packages get a credential — the
# platform never holds a GitHub token), and jq.
#
# Auth: the platform derives a per-install secret (HMAC over the core secret —
# never stored) and injects its sha256 hex as HASHED_PASSWORD. code-server's
# `--auth password` gate then accepts exactly that hex string as its
# `code-server-session` cookie, and core-server's pin-cookie proxy injects that
# cookie on every request, so the owner types nothing (cs#350). The derived
# secret itself still works on the login form as break-glass. PASSWORD (plain
# text) still works for standalone runs. The proxy is the outer wall — the
# container is never published to the internet directly.
#
# Build:
#   docker build -t cfg-server-codeserver:local .
#
# Run (local test):
#   docker run --rm -p 8080:8080 -e PASSWORD=dev -v /tmp/coder-home:/home/coder cfg-server-codeserver:local

ARG CODE_SERVER_VERSION=4.139.1

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
# already ships curl (the HEALTHCHECK needs it), git, git-lfs and sudo. We add
# Node 24, gh and jq from their vendors' apt repos, then our entrypoint.
#
# Why each odd-looking choice below:
#   - The NodeSource key is fetched at build time and kept ARMORED (.asc):
#     apt reads armored keys from signed-by, and the base has no gnupg for
#     `gpg --dearmor`. Never vendor it — NodeSource re-issued it under the same
#     fingerprint to fix a SHA1 rejection, so a stale copy fails on trixie.
#   - The gh keyring is checked against a pinned sha256 (taken from a fresh
#     download, 2026-09-25). If cli.github.com rotates it, this build fails
#     loudly — re-download, verify, and update the hash.
#   - gh's suite is `stable`, not `$(lsb_release -cs)`: there is no trixie suite
#     (it 404s).
#   - NodeSource's nodejs hard-depends on python3 (for node-gyp), so python3
#     comes along and adds to the image size.
#   - The trailing version checks make a wrong Node major (e.g. a NodeSource
#     repo change) fail the build instead of shipping.
USER root
RUN set -eux; \
    install -d -m 0755 /etc/apt/keyrings; \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key -o /etc/apt/keyrings/nodesource.asc; \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /etc/apt/keyrings/githubcli-archive-keyring.gpg; \
    echo '6084d5d7bd8e288441e0e94fc6275570895da18e6751f70f057485dc2d1a811b  /etc/apt/keyrings/githubcli-archive-keyring.gpg' \
      | sha256sum -c -; \
    chmod a+r /etc/apt/keyrings/nodesource.asc /etc/apt/keyrings/githubcli-archive-keyring.gpg; \
    arch="$(dpkg --print-architecture)"; \
    echo "deb [arch=${arch} signed-by=/etc/apt/keyrings/nodesource.asc] https://deb.nodesource.com/node_24.x nodistro main" \
      > /etc/apt/sources.list.d/nodesource.list; \
    echo "deb [arch=${arch} signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends nodejs gh jq; \
    rm -rf /var/lib/apt/lists/*; \
    node --version | grep -q '^v24\.'; \
    gh --version

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

# Env knobs (defaults suit standalone runs):
#   HASHED_PASSWORD       — what the platform sets: sha256 hex of the
#                           per-install derived secret, which code-server
#                           accepts verbatim as its session cookie (cs#350)
#   PASSWORD              — plain-text password for standalone runs
#   CODESERVER_APP_NAME   — branding shown on the login page; an image default
#                           only, the launcher does not set it
ENV CODESERVER_APP_NAME="CFG code-server"

# dumb-init comes from the upstream image; our entrypoint execs code-server
# under it so SIGTERM lands cleanly on `docker stop`.
ENTRYPOINT ["/usr/bin/dumb-init", "--", "/usr/local/bin/cfg-entrypoint.sh"]
