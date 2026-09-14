#!/usr/bin/env bash
# Serves the landing page, the app, and the browser build on your local
# network, so a phone on the same wifi can install or try Split the Bill.
# Nothing leaves your network.
#
#   ./serve.sh          then open the printed address on the phone
#
# Ctrl+C to stop.
set -euo pipefail
cd "$(dirname "$0")/dist"

PORT="${1:-8000}"
IP="$(hostname -I | awk '{print $1}')"

cat <<EOF

  Split the Bill is being served on your network.

  On your phone, connected to the same wifi, open:

      http://$IP:$PORT/

  That is the landing page, with the download on it.

  Android will warn that the app is from an unknown source. That is what
  installing outside the Play Store looks like; allow it for your browser
  when prompted.

  Already have an older version? Uninstall it first. This build is signed
  with a different key, so Android will refuse to install over the old one.

  Ctrl+C to stop the server.

EOF

python3 -m http.server "$PORT"
