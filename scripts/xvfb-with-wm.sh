#!/usr/bin/env bash
# Run a Flutter Linux integration test under xvfb + openbox so GTK window
# operations (resize, iconify, maximize) take real effect. Without a WM,
# gtk_window_resize and friends are silent no-ops under raw xvfb.
#
# Usage: scripts/xvfb-with-wm.sh <command...>
#   e.g. scripts/xvfb-with-wm.sh flutter test integration_test/ -d linux

set -euo pipefail

if ! command -v xvfb-run >/dev/null; then
  echo "xvfb-run not found. Run: sudo apt-get install -y xvfb" >&2
  exit 1
fi
if ! command -v openbox >/dev/null; then
  echo "openbox not found. Run: sudo apt-get install -y openbox" >&2
  exit 1
fi

DISPLAY_NUM=99
SCREEN_GEO="1920x1080x24"

Xvfb ":${DISPLAY_NUM}" -screen 0 "${SCREEN_GEO}" -nolisten tcp &
XVFB_PID=$!
trap 'kill $XVFB_PID 2>/dev/null || true' EXIT

# Wait for X server to be ready
for _ in $(seq 1 30); do
  if DISPLAY=":${DISPLAY_NUM}" xset -q >/dev/null 2>&1; then break; fi
  sleep 0.1
done

export DISPLAY=":${DISPLAY_NUM}"
export GDK_BACKEND=x11

openbox --config-file /dev/null &
OPENBOX_PID=$!
trap 'kill $OPENBOX_PID 2>/dev/null; kill $XVFB_PID 2>/dev/null || true' EXIT

# Give openbox a moment to grab the root window
sleep 0.5

exec "$@"
