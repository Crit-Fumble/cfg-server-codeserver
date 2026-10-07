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
4. PR against `next` — the release-candidate branch. A push to `next` publishes
   `:next`; `:latest`, which the platform pulls by default, moves only on a `v*` tag.

## Version bumps

The upstream version lives only in `ARG CODE_SERVER_VERSION` in the Dockerfile —
build.yml reads it from there, so never restate it in the workflow. dev-tools'
upstream-watch opens a bump PR into `next` when upstream releases.

## Conventions

- Keep the image thin: beyond upstream code-server it adds only Node 24, `gh`
  and `jq` (see the README's "What is on the box"); anything else a user wants
  belongs in their `/home/coder`.
- No secrets in the image or the repo — on the platform, auth arrives at
  container start as a `HASHED_PASSWORD` env value the launcher mints fresh per
  launch; `PASSWORD` is for standalone runs only.
