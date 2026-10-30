#!/usr/bin/env bash
# Run the dev build of wivrn-dashboard (scripts/build-dashboard.sh) with build/wivrn's server.
#   scripts/run-dashboard.sh [wivrn-server args...]    e.g. --no-manage-active-runtime; the dashboard passes them on
# The dashboard starts a private dbus-daemon ($(getconf DARWIN_USER_TEMP_DIR)wivrn/dbus-<pid>) and the server on it.
# Don't run it next to another wivrn-server: both want port 9757 and the same comp_ipc socket.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KDE="$ROOT/build/kde/prefix"
export QML_IMPORT_PATH="$KDE/lib/qml" QT_PLUGIN_PATH="$KDE/lib/plugins"
export WIVRN_SERVER="${WIVRN_SERVER:-${WIVRN_BUILD_DIR:-$ROOT/build/wivrn}/server/wivrn-server}"
export XRT_LOG="${XRT_LOG:-info}"
exec "${WIVRN_DASHBOARD_BUILD_DIR:-$ROOT/build/wivrn-dashboard}/server/wivrn-dashboard.app/Contents/MacOS/wivrn-dashboard" "$@"
