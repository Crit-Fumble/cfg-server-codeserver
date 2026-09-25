# cfg-server-codeserver

The platform's hosted **code-server** — [code-server](https://github.com/coder/code-server) (VS
Code in the browser, MIT) packaged as a Crit-Fumble **tool-server** kind: a
per-user hosted dev environment, provisioned one container per installation by
core-server's Server Manager and billed per 10-minute interval while it runs,
plus a final remainder at stop (dt#204).

This repo is a thin container around upstream code-server — a `Dockerfile`, an
`entrypoint.sh`, and nothing else. Docker is the only prerequisite.

## What the platform expects of this image

| Contract | Value |
| --- | --- |
| App port | `8080/tcp` (semantic docker port label, host port auto-assigned) |
| Health | `HEALTHCHECK` against code-server's `/healthz` — the platform's status + proxy paths gate on docker health |
| Persistent data | `/home/coder` (bind mount of the installation data dir — settings, extensions, repos all survive replacement) |
| Auth (platform) | `HASHED_PASSWORD` env, injected by the launcher; the platform's proxy supplies the matching cookie (below) |
| Auth (standalone) | `PASSWORD` env — a plain-text password typed into code-server's login form |
| Shutdown | SIGTERM via dumb-init (upstream PID 1) |

On the platform, the launcher derives a per-install secret (HMAC over the core
secret, never stored) and injects its sha256 hex as `HASHED_PASSWORD`.
code-server accepts that hex string verbatim as its `code-server-session`
cookie, and the platform's proxy adds the cookie to every request, so the owner
never sees a login form. The derived secret still works on the login form as a
fallback.

That cookie behavior is code-server's SHA256 path, which upstream labels
"legacy". The PR build smoke-tests it, so an upstream bump that drops it fails
CI here rather than in production.

## What is on the box

- code-server at the version pinned by `ARG CODE_SERVER_VERSION` in the `Dockerfile`
- Node.js 24 (from NodeSource) with npm, plus the python3 it depends on for native addons
- GitHub CLI `gh` (from cli.github.com)
- `jq`
- From the upstream image: `git`, `git-lfs`, `curl`, `zsh`, and passwordless `sudo` for the `coder` user

## Using GitHub inside the box

The platform never holds a GitHub token. You sign in as yourself, inside the
box, from the built-in terminal:

```bash
git config --global user.name "Your Name"
git config --global user.email "<id>+<username>@users.noreply.github.com"

# Device flow: prints a one-time code; open the URL in your own browser.
gh auth login --hostname github.com --git-protocol https --web --scopes read:packages,workflow
# Makes git use gh's token for https://github.com (safe to re-run).
gh auth setup-git

# Install dependencies from GitHub Packages without writing the token to disk.
env "npm_config_//npm.pkg.github.com/:_authToken=$(gh auth token)" npm ci
```

Never run `npm config set //npm.pkg.github.com/:_authToken=...`: it writes the
token in plain text to `~/.npmrc`.

The box has no system keyring, so `gh` keeps its token in plain text in
`~/.config/gh/hosts.yml` and prints a warning saying so. That is expected here.
`gh auth logout` removes it.

VS Code's own GitHub sign-in (the Accounts menu) is optional. `git push` from
the terminal or the Source Control view uses `gh`'s credential helper.

## What the platform does not back up

`/home/coder` survives container replacement, and the platform backs it up,
except for these paths, which it leaves out of its storage backup:

- `~/.config/gh` (your `gh` token)
- `.npmrc` and `.git-credentials`, anywhere
- `~/.npm` and `~/.cache`
- `node_modules`, at any depth

After a restore, run `gh auth login`, `gh auth setup-git` and `npm ci` again.

Shell history *is* backed up. Never paste a raw token into the shell.

## Local test

```bash
docker build -t cfg-server-codeserver:local .
mkdir -p /tmp/coder-home

# Plain password, typed into the login form:
docker run --rm -p 8080:8080 -e PASSWORD=dev -v /tmp/coder-home:/home/coder cfg-server-codeserver:local
# → http://localhost:8080 (password: dev)

# The platform's form: the hash is the session cookie, no login form.
hash=$(printf '%s' dev | sha256sum | cut -d' ' -f1)   # macOS: shasum -a 256
docker run -d --name cs-local -p 8080:8080 -e HASHED_PASSWORD="$hash" -v /tmp/coder-home:/home/coder cfg-server-codeserver:local
# Bare /vscode/ is a 302 to ?folder= even when signed in; the folder URL is the 200.
curl -s -o /dev/null -w '%{http_code}\n' -H "Cookie: code-server-session=$hash" \
  'http://localhost:8080/vscode/?folder=/home/coder/projects'   # → 200 once up (a 302 to /login means the cookie was refused)
# The login form at http://localhost:8080 still accepts "dev".
docker rm -f cs-local
```

On Linux the container runs as uid 1000, so `/tmp/coder-home` must be writable
by it (`sudo chown 1000:1000 /tmp/coder-home`).

## Gating

Alpha: admin-only (the kind is hidden from the Create Server picker and the
installation POST rejects non-admins). Dev+ users come later, behind the
GitHub-App credential story — see dt#204 for the ladder.

## License

AGPL-3.0-only (this scaffold). Upstream code-server is MIT.
