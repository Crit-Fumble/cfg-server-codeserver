# syntax=docker/dockerfile:1.7
#
# cfg-server-codeserver — per-user hosted code-server (VS Code in
# the browser, coder/code-server, MIT) as a hosted tool-server kind (dt#204).
#
# The platform provisions ONE container per UserAppInstallation through the
# Server Manager kind registry (kinds/codeserver.ts → services/codeserver/
# launch.ts), CT-metered like every other kind: per 10-minute interval while
# it runs, plus a final remainder at stop. Alpha-gated (admin-only).
#
# Everything the user owns lives under /home/coder — the platform bind-mounts
# the installation's data dir there, so extensions, settings
# (~/.local/share/code-server), and checked-out repos survive container
# replacement. The image itself stays disposable.
#
# The box is for developing the CFG repos, so it ships what they need on top
# of upstream: Node 24 (the repos' engines floor), the GitHub CLI (the user's
# own `gh auth login` is how git and GitHub Packages get a credential — the
# platform never holds a GitHub token), jq, gitleaks (every private CFG repo's
# pre-commit hook refuses to commit without it) and the system libraries
# Playwright's Chromium needs. It ships no sudo: nothing a user runs can become
# root, so anything that needs root has to be in the image.
#
# Auth: the platform mints a fresh random value at every launch (32 bytes as
# hex, never stored) and injects it as HASHED_PASSWORD. code-server's
# `--auth password` gate then accepts exactly that hex string as its
# `code-server-session` cookie, and core-server's pin-cookie proxy injects that
# cookie on every request, so the owner types nothing (cs#350). No password
# typed into the login form matches it. PASSWORD (plain text) still works for
# standalone runs. The proxy is the outer wall — the container is never
# published to the internet directly.
#
# Build:
#   docker build -t cfg-server-codeserver:local .
#
# Run (local test):
#   docker run --rm -p 8080:8080 -e PASSWORD=dev -v /tmp/coder-home:/home/coder cfg-server-codeserver:local

ARG CODE_SERVER_VERSION=4.143.1

FROM codercom/code-server:${CODE_SERVER_VERSION}

ARG CODE_SERVER_VERSION
# The Playwright whose Chromium dependency list the image installs: the
# `@playwright/test` cfg-core-dev-tools' e2e suite pins. Bump it with that.
ARG PLAYWRIGHT_VERSION=1.64.1
ARG GITLEAKS_VERSION=8.30.1
ARG GITLEAKS_SHA256=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb

LABEL org.opencontainers.image.title="cfg-server-codeserver" \
      org.opencontainers.image.description="CodeBench — per-user code-server (VS Code in the browser) tool-server kind" \
      org.opencontainers.image.source="https://github.com/Crit-Fumble/cfg-server-codeserver" \
      org.opencontainers.image.licenses="AGPL-3.0-only" \
      org.opencontainers.image.version="${CODE_SERVER_VERSION}"

# ⚠️ `org.opencontainers.image.version` above does NOT survive to the published
# image: docker/metadata-action emits its own OCI label set and `--label`
# last-wins, so the release workflow overwrites it with the git tag (e.g.
# v0.1.0). Auditing "what upstream is in here?" via the OCI label therefore reads
# back OUR tag. The cfg.* namespace survives because the metadata action never
# emits it.
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
#     download). If cli.github.com rotates it, this build fails loudly —
#     re-download, verify, and update the hash.
#   - gh's suite is `stable`, not `$(lsb_release -cs)`: there is no trixie suite
#     (it 404s).
#   - NodeSource's nodejs hard-depends on python3 (for node-gyp), so python3
#     comes along and adds to the image size.
#   - The trailing version checks make a wrong Node major (e.g. a NodeSource
#     repo change) fail the build instead of shipping.
#   - code-server's own Node (`lib/node`: the server, the extension host and
#     everything they start) becomes a link to the NodeSource one, so its TLS
#     root store is the one this layer installs, not the one upstream bundled.
#     NODE_OPTIONS cannot do it: VS Code removes that from the extension host
#     the same way it removes LD_PRELOAD. The ABI check fails the build if
#     upstream moves to a Node whose native modules would not load on ours.
#   - ca-certificates is upgraded at build time, so git, curl and gh verify
#     against the Debian bundle of that build rather than the base image's.
#   - /etc/passwd and /etc/group are writable by every uid so the entrypoint
#     can give a uid with no entry the name `coder` (see entrypoint.sh). An
#     entry in the files reaches every process; an LD_PRELOAD shim does not,
#     because VS Code removes LD_PRELOAD from the extension host and everything
#     it starts (#21). The upstream image does this with fixuid, a setuid
#     helper: it never runs here, since this image replaces upstream's
#     entrypoint, and it could not under no-new-privileges. Anyone in the
#     container can edit the files, which names a uid and grants nothing.
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
    apt-get install -y --no-install-recommends nodejs gh jq ca-certificates; \
    rm -rf /var/lib/apt/lists/*; \
    node --version | grep -q '^v24\.'; \
    test "$(/usr/lib/code-server/lib/node -p process.versions.modules)" = "$(node -p process.versions.modules)"; \
    ln -sf /usr/bin/node /usr/lib/code-server/lib/node; \
    gh --version; \
    chmod 0666 /etc/passwd /etc/group

# The CFG repos' tooling, and the end of root:
#   - gitleaks is the release binary, checked against a pinned sha256 of the
#     tarball (from the release's checksums file).
#   - Chromium's libraries come from Playwright's own list for this OS, at the
#     repos' Playwright version. The browser itself is not in the image: each
#     repo's `npx playwright install chromium` puts its matching build in
#     ~/.cache, which needs no root once these libraries exist.
#   - sudo is purged (cs#550). Upstream ships it passwordless for `coder`; on
#     CFG hosting no-new-privileges already made it useless, and the dev
#     tooling now gets from the image what it used to ask sudo for.
#   - ~/.local/bin is where a user installs their own tools, and the home
#     starts with no shell rc to put it on PATH. ENV covers every process;
#     /etc/profile resets PATH in bash and sh login shells, so profile.d puts it
#     back there.
RUN set -eux; \
    tmp="$(mktemp -d)"; \
    curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" \
      -o "$tmp/gitleaks.tar.gz"; \
    echo "${GITLEAKS_SHA256}  $tmp/gitleaks.tar.gz" | sha256sum -c -; \
    tar -xzf "$tmp/gitleaks.tar.gz" -C "$tmp" gitleaks; \
    install -m 0755 "$tmp/gitleaks" /usr/local/bin/gitleaks; \
    rm -rf "$tmp"; \
    gitleaks version; \
    npx -y "playwright@${PLAYWRIGHT_VERSION}" install-deps chromium; \
    rm -rf /var/lib/apt/lists/* /root/.npm; \
    apt-get purge -y sudo; \
    rm -rf /etc/sudoers /etc/sudoers.d; \
    test -z "$(command -v sudo)"; \
    printf '%s\n' 'case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$HOME/.local/bin:$PATH" ;; esac' \
      > /etc/profile.d/cfg-local-bin.sh

COPY entrypoint.sh /usr/local/bin/cfg-entrypoint.sh
RUN chmod +x /usr/local/bin/cfg-entrypoint.sh
USER coder
# Docker takes HOME from /etc/passwd, and a uid given with `--user` has no
# entry there: HOME would be `/`, and the entrypoint's first mkdir would fail.
ENV HOME=/home/coder
ENV PATH=/home/coder/.local/bin:${PATH}

# code-server's own liveness endpoint — unauthenticated by design. The
# platform's status/proxy paths gate on docker health being `healthy`, so a
# real HEALTHCHECK here is load-bearing (port-bound alone is a wrong signal:
# code-server binds instantly, before the workbench can serve).
HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8080/healthz || exit 1

EXPOSE 8080/tcp

# Env knobs (defaults suit standalone runs):
#   HASHED_PASSWORD       — what the platform sets: a fresh random hex value
#                           per launch, which code-server accepts verbatim
#                           as its session cookie (cs#350)
#   PASSWORD              — plain-text password for standalone runs
#   CODESERVER_APP_NAME   — branding shown on the login page; an image default
#                           only, the launcher does not set it
ENV CODESERVER_APP_NAME="CFG code-server"

# dumb-init comes from the upstream image; our entrypoint execs code-server
# under it so SIGTERM lands cleanly on `docker stop`.
ENTRYPOINT ["/usr/bin/dumb-init", "--", "/usr/local/bin/cfg-entrypoint.sh"]
