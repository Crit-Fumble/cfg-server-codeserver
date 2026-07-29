# cfg-server-codeserver

The platform's hosted **code-server** — [code-server](https://github.com/coder/code-server) (VS
Code in the browser, MIT) packaged as a Crit-Fumble **tool-server** kind: a
per-user hosted dev environment, provisioned one container per installation by
core-server's Server Manager and billed by active minute (dt#204).

This repo is a thin container around upstream code-server — a `Dockerfile`, an
`entrypoint.sh`, and nothing else. Docker is the only prerequisite.

## What the platform expects of this image

| Contract | Value |
| --- | --- |
| App port | `8080/tcp` (semantic docker port label, host port auto-assigned) |
| Health | `HEALTHCHECK` against code-server's `/healthz` — the platform's status + proxy paths gate on docker health |
| Persistent data | `/home/coder` (bind mount of the installation data dir — settings, extensions, repos all survive replacement) |
| Auth | `PASSWORD` env — derived per-install by the launcher (HMAC over the core secret), never stored |
| Shutdown | SIGTERM via dumb-init (upstream PID 1) |

## Local test

```bash
docker build -t cfg-server-codeserver:local .
docker run --rm -p 8080:8080 -e PASSWORD=dev -v /tmp/coder-home:/home/coder cfg-server-codeserver:local
# → http://localhost:8080 (password: dev)
```

## Gating

Alpha: admin-only (the kind is hidden from the Create Server picker and the
installation POST rejects non-admins). Dev+ users come later, behind the
GitHub-App credential story — see dt#204 for the ladder.

## License

AGPL-3.0-only (this scaffold). Upstream code-server is MIT.
