# Contributing to cfg-server-codeserver

This repo is a thin container around upstream
[code-server](https://github.com/coder/code-server) — a `Dockerfile`, an
`entrypoint.sh`, and nothing else. There is no Node toolchain and no test
suite; **Docker is the only prerequisite**.

## Workflow

1. Build locally: `docker build -t cfg-server-codeserver:local .`
2. Smoke it: `docker run --rm -p 8080:8080 -e PASSWORD=dev cfg-server-codeserver:local`
   then open http://localhost:8080 and sign in.
3. Verify health flips to `healthy`: `docker inspect --format '{{.State.Health.Status}}' <id>`
4. PR against `next` — the release-candidate branch. A merge to `next` publishes
   `ghcr.io/crit-fumble/cfg-server-codeserver:latest`.

## Version bumps

Upstream version is pinned by `ARG CODE_SERVER_VERSION` (Dockerfile) and the
default in `.github/workflows/build.yml` — bump BOTH in one commit. Pinning
means no auto-update: someone must actually do this on upstream releases.

## Conventions

- Keep the image thin: user tooling belongs in the user's `/home/coder`, not
  baked into the image.
- No secrets in the image or the repo — auth arrives as `PASSWORD` env from
  the platform launcher at container start.
