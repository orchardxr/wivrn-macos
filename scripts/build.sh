#!/usr/bin/env bash
# Build everything into the install tree. Run scripts/patches.sh apply first.
#   scripts/build.sh [step...]     default: all steps below, in this order
#
# openxr-sdk  native OpenXR loader + hello_xr (build/openxr-sdk), for the test programs
# server      wivrn-server (build/wivrn), refreshing build/monado-snapshot from the staged third_party/monado
# clients     x86_64 and arm64 libopenxr_wivrn (build/wivrn-client-{x86_64,arm64})
# tests       build/tests/{xr_empty_frames,xr_metal,audio_tone}
# install     scripts/install.sh: build/install (WIVRN_INSTALL_DIR)
# dashboard-deps  scripts/build-dashboard-deps.sh: KDE frameworks Homebrew lacks, build/kde/prefix (skipped when built)
# dashboard   scripts/build-dashboard.sh: build/wivrn-dashboard
# app         scripts/build-app.sh: build/WiVRn.app
# Logs: build/logs/
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib/ccache.sh"
LOGS="$ROOT/build/logs"
mkdir -p "$LOGS"

openxr_sdk() {
	local b="$ROOT/build/openxr-sdk"
	echo "==> configure openxr-sdk"
	cmake -S "$ROOT/third_party/openxr-sdk" -B "$b" -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo \
		-DBUILD_TESTS=ON -DBUILD_CONFORMANCE_TESTS=OFF -DDYNAMIC_LOADER=ON -DBUILD_WITH_SYSTEM_JSONCPP=OFF \
		> "$LOGS/openxr-sdk-configure.log" 2>&1 || { tail -30 "$LOGS/openxr-sdk-configure.log"; exit 1; }
	echo "==> build openxr-sdk"
	ninja -C "$b" openxr_loader hello_xr > "$LOGS/openxr-sdk-build.log" 2>&1 \
		|| { grep -E "error|FAILED" "$LOGS/openxr-sdk-build.log" | head -30; exit 1; }
}

tests() {
	local t="$ROOT/build/tests" sdk="$ROOT/build/openxr-sdk"
	[[ -f "$sdk/src/loader/libopenxr_loader.dylib" ]] || { echo "no OpenXR loader: run the openxr-sdk step" >&2; exit 1; }
	echo "==> build tests"
	mkdir -p "$t"
	# drives the compositor without an application swapchain
	clang -O1 -Wall -o "$t/xr_empty_frames" "$ROOT/tests/wivrn/xr_empty_frames.c" \
		-I"$ROOT/third_party/openxr-sdk/include" -I"$sdk/include" -I/usr/local/include \
		-L"$sdk/src/loader" -lopenxr_loader -L/usr/local/lib -lvulkan \
		-Wl,-rpath,"$sdk/src/loader" -Wl,-rpath,/usr/local/lib
	# native Metal OpenXR app (XR_KHR_metal_enable)
	clang -fobjc-arc -O1 -Wall -o "$t/xr_metal" "$ROOT/tests/metal-xr/xr_metal.m" \
		-I"$ROOT/third_party/openxr-sdk/include" -I"$sdk/include" \
		-L"$sdk/src/loader" -lopenxr_loader \
		-Wl,-rpath,"$sdk/src/loader" -framework Metal -framework Foundation
	# test tone for the CoreAudio backend
	clang++ -std=c++20 -fobjc-arc -O1 -o "$t/audio_tone" "$ROOT/tests/wivrn/audio_tone.mm" \
		-framework AudioToolbox -framework CoreAudio -framework Foundation
}

steps=("$@")
[[ ${#steps[@]} -gt 0 ]] || steps=(openxr-sdk server clients tests install dashboard-deps dashboard app)
for s in "${steps[@]}"; do
	case "$s" in
		openxr-sdk) openxr_sdk ;;
		server) "$ROOT/scripts/build-wivrn.sh" --snapshot ;;
		clients)
			"$ROOT/scripts/build-wivrn.sh" --client-x86_64
			"$ROOT/scripts/build-wivrn.sh" --client-arm64 ;;
		tests) tests ;;
		install) "$ROOT/scripts/install.sh" ;;
		dashboard-deps)
			[[ -f "$ROOT/build/kde/prefix/lib/cmake/QCoro6/QCoro6Config.cmake" ]] || "$ROOT/scripts/build-dashboard-deps.sh" ;;
		dashboard) "$ROOT/scripts/build-dashboard.sh" ;;
		app) "$ROOT/scripts/build-app.sh" ;;
		*) echo "unknown step $s" >&2; exit 2 ;;
	esac
done
echo "==> done"
