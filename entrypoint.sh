#!/usr/bin/env bash
#
# cfg-server-codeserver entrypoint.
#
# /home/coder is a bind mount of the installation's data dir, so on first
# boot it is EMPTY — the image's own home skeleton is shadowed. Seed the
# minimal bits code-server expects, then exec code-server (dumb-init is PID 1
# above us and forwards SIGTERM).
#
# Env knobs (set by core-server's launcher; defaults suit standalone runs):
#   PASSWORD            — password auth for code-server (blank ⇒ auth stays
#                         on; code-server generates one into its config —
#                         standalone `docker run` users read it from the log.
#                         The platform ALWAYS sets it.)
#   CODESERVER_APP_NAME — login-page branding (default: CFG Dev Box)

set -euo pipefail

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
  --app-name "${CODESERVER_APP_NAME:-CFG Dev Box}" \
  "$HOME/projects"
