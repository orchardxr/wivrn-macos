#!/usr/bin/env bash
# Configure and build wivrn-dashboard (third_party/wivrn/dashboard, patched) on macOS.
#   scripts/build-dashboard.sh [ninja args...]     WIVRN_DASHBOARD_BUILD_DIR=... overrides build/wivrn-dashboard
# Needs the KDE prefix from scripts/build-dashboard-deps.sh. Output: build/wivrn-dashboard/server/wivrn-dashboard.app
# Logs: build/logs/wivrn-dashboard-{configure,build}.log
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib/ccache.sh"
LOGS="$ROOT/build/logs"
BUILD="${WIVRN_DASHBOARD_BUILD_DIR:-$ROOT/build/wivrn-dashboard}"
KDE="$ROOT/build/kde/prefix"
mkdir -p "$LOGS"
[[ -d "$KDE/lib/cmake/KF6Kirigami" ]] || { echo "no $KDE: run scripts/build-dashboard-deps.sh" >&2; exit 1; }

if [[ ! -f "$BUILD/build.ninja" ]]; then
	echo "==> configure wivrn-dashboard"
	cmake -S "$ROOT/third_party/wivrn" -B "$BUILD" -G Ninja \
		-DCMAKE_BUILD_TYPE="${WIVRN_BUILD_TYPE:-RelWithDebInfo}" \
		-DCMAKE_PREFIX_PATH="$KDE;/opt/homebrew/opt/qt;/opt/homebrew/opt/libarchive;/opt/homebrew" \
		-DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
		-DKDE_INSTALL_QMLDIR="$KDE/lib/qml" -DGIT_TAG=v26.9 \
		-DWIVRN_BUILD_SERVER=OFF -DWIVRN_BUILD_CLIENT=OFF -DWIVRN_BUILD_DASHBOARD=ON -DWIVRN_BUILD_WIVRNCTL=OFF \
		> "$LOGS/wivrn-dashboard-configure.log" 2>&1 \
		|| { tail -40 "$LOGS/wivrn-dashboard-configure.log"; exit 1; }
fi

echo "==> build wivrn-dashboard"
ninja -C "$BUILD" wivrn-dashboard "$@" > "$LOGS/wivrn-dashboard-build.log" 2>&1 \
	|| { grep -E "error:|FAILED" "$LOGS/wivrn-dashboard-build.log" | cut -c1-300 | head -40; exit 1; }
echo "==> done: $BUILD/server/wivrn-dashboard.app"
