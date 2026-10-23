#!/usr/bin/env bash
#
# cfg-server-codeserver entrypoint.
#
# /home/coder is a bind mount of the installation's data dir, so on first
# boot it is EMPTY — the image's own home skeleton is shadowed. Seed the
# minimal bits code-server expects, then exec code-server (dumb-init is PID 1
# above us and forwards SIGTERM).
#
# Env knobs (defaults suit standalone runs). code-server reads the auth ones
# from its own environment, so this script never touches them:
#   HASHED_PASSWORD     — what the platform ALWAYS sets: a fresh random hex
#                         value per launch. code-server accepts that hex
#                         verbatim as its session cookie, which core-server's
#                         proxy injects so the owner types nothing (cs#350).
#   PASSWORD            — plain-text password for standalone runs (both blank
#                         ⇒ auth stays on; code-server generates one into its
#                         config and standalone `docker run` users read it from
#                         ~/.config/code-server/config.yaml).
#   CODESERVER_APP_NAME — login-page branding; an image default (CFG
#                         code-server), the launcher does not set it

set -euo pipefail

# A uid with no passwd entry (`docker run --user`, or the platform starting each
# member's server as that member's own uid) is not cosmetic: ssh refuses to run
# ("No user exists for uid"), which kills git over ssh, and whoami and Node's
# os.userInfo() fail. So `coder` takes this uid in /etc/passwd itself (the
# image leaves it writable), which every process reads whatever its
# environment: VS Code strips LD_PRELOAD from its extension host, so a preload
# shim never reached git in the Source Control panel (#21). Each file is read
# whole before it is rewritten, in place, since /etc is not writable. A
# restarted container keeps its entry and skips this. On a read-only root
# filesystem the uid stays nameless and code-server still starts.
if ! getent passwd "$(id -u)" > /dev/null; then
  passwd="$(sed "s/^coder:x:[0-9]*:[0-9]*:/coder:x:$(id -u):$(id -g):/" /etc/passwd)"
  printf '%s\n' "$passwd" > /etc/passwd \
    || echo "cfg-entrypoint: cannot write /etc/passwd; uid $(id -u) has no name, so ssh will refuse it" >&2
  if ! getent group "$(id -g)" > /dev/null; then
    group="$(sed "s/^coder:x:[0-9]*:/coder:x:$(id -g):/" /etc/group)"
    printf '%s\n' "$group" > /etc/group || true
  fi
fi

# Seed a default user settings file once — dark theme, telemetry off. Never
# overwrite: after first boot this file belongs to the user.
SETTINGS_DIR="$HOME/.local/share/code-server/User"
if [ ! -f "$SETTINGS_DIR/settings.json" ]; then
  mkdir -p "$SETTINGS_DIR"
  cat > "$SETTINGS_DIR/settings.json" << 'JSON'
{
  "workbench.colorTheme": "Default Dark Modern",
  "telemetry.telemetryLevel": "off"
}
JSON
fi

# A friendly first-boot workspace dir so the file explorer doesn't open on an
# empty home full of dotfiles.
mkdir -p "$HOME/projects"

exec code-server \
  --bind-addr 0.0.0.0:8080 \
  --auth password \
  --disable-telemetry \
  --disable-update-check \
  --app-name "${CODESERVER_APP_NAME:-CFG code-server}" \
  "$HOME/projects"
