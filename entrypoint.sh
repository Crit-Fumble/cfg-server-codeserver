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
# os.userInfo() fail. nss_wrapper answers those lookups from a copy of
# /etc/passwd in which `coder` carries this uid; /etc/passwd itself stays
# read-only. Every terminal the workbench opens inherits the three variables.
if ! getent passwd "$(id -u)" > /dev/null; then
  nss_dir="$(mktemp -d)"
  sed "s/^coder:x:[0-9]*:[0-9]*:/coder:x:$(id -u):$(id -g):/" /etc/passwd > "$nss_dir/passwd"
  cp /etc/group "$nss_dir/group"
  getent group "$(id -g)" > /dev/null || sed -i "s/^coder:x:[0-9]*:/coder:x:$(id -g):/" "$nss_dir/group"
  export NSS_WRAPPER_PASSWD="$nss_dir/passwd" NSS_WRAPPER_GROUP="$nss_dir/group"
  export LD_PRELOAD="libnss_wrapper.so${LD_PRELOAD:+:$LD_PRELOAD}"
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
