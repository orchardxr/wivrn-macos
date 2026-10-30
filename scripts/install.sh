#!/usr/bin/env bash
# Assemble the install tree from the server and client builds (scripts/build.sh server clients).
#   scripts/install.sh            WIVRN_INSTALL_DIR=... overrides build/install
#
# bin/wivrn-server                        launcher: points Vulkan at the bundled MoltenVK, runs libexec/wivrn/wivrn-server
# libexec/wivrn/wivrn-server              the server (arm64)
# lib/*.dylib                             the server's Homebrew / Vulkan SDK dylibs and MoltenVK, @rpath
# lib/wivrn/libopenxr_wivrn.dylib         OpenXR runtime, IPC client only, universal (x86_64 arm64)
# share/openxr/1/openxr_wivrn.json        its manifest (relative library_path)
# share/vulkan/icd.d/MoltenVK_icd.json    ICD manifest of the bundled MoltenVK
# share/wivrn/ipc-stamp                   IPC stamp of the server, equal to both client slices' (scripts/ipc-stamp.sh)
# share/wivrn/build-info                  version= (VERSION), this repo, WiVRn tag, Monado tree, patch lists, configured prefix
# share/doc/wivrn-macos/                  licenses
#
# The tree is self-contained (no Homebrew or Vulkan SDK at run time) and ad-hoc signed.
set -Eeuo pipefail
trap 'echo "install.sh: failed at line $LINENO: $BASH_COMMAND" >&2' ERR
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib/bundle-dylibs.sh"
SERVER="${WIVRN_BUILD_DIR:-$ROOT/build/wivrn}"
CX86="${WIVRN_CLIENT_X86_64_DIR:-$ROOT/build/wivrn-client-x86_64}/client"
CARM="${WIVRN_CLIENT_ARM64_DIR:-$ROOT/build/wivrn-client-arm64}/client"
DEST="${WIVRN_INSTALL_DIR:-$ROOT/build/install}"

die() { echo "install.sh: $*" >&2; exit 1; }
for f in "$SERVER/server/wivrn-server" "$SERVER/server/ipc-stamp" "$CX86/libopenxr_wivrn.dylib" "$CX86/ipc-stamp" \
	"$CARM/libopenxr_wivrn.dylib" "$CARM/ipc-stamp"; do
	[[ -f "$f" ]] || die "missing $f (scripts/build.sh server clients)"
done
for c in "$CX86" "$CARM"; do
	cmp -s "$SERVER/server/ipc-stamp" "$c/ipc-stamp" \
		|| die "ipc-stamp of $c differs from the server's: rebuild the clients (scripts/build.sh clients)"
done
prefix="$(sed -n 's/^CMAKE_INSTALL_PREFIX:[A-Z]*=//p' "$SERVER/CMakeCache.txt")"

delete_rpaths() {
	local r
	for r in $(otool -l "$1" | awk '$1 == "cmd" { c = $2 } c == "LC_RPATH" && $1 == "path" { print $2 }' | sort -u); do
		install_name_tool -delete_rpath "$r" "$1" 2>/dev/null
	done
}

echo "==> install $DEST"
new="$DEST.new"
rm -rf "$new"
mkdir -p "$new/bin" "$new/libexec/wivrn" "$new/lib/wivrn" "$new/share/openxr/1" "$new/share/vulkan/icd.d" \
	"$new/share/wivrn" "$new/share/doc/wivrn-macos"

srv="$new/libexec/wivrn/wivrn-server"
cp "$SERVER/server/wivrn-server" "$srv"
chmod u+w "$srv"
delete_rpaths "$srv"
install_name_tool -add_rpath @loader_path/../../lib "$srv"
bundle_dylibs "$new/lib" "$srv"

mvk="$(brew --prefix molten-vk)"
cp -L "$mvk/lib/libMoltenVK.dylib" "$new/lib/"
chmod u+w "$new/lib/libMoltenVK.dylib"
install_name_tool -id @rpath/libMoltenVK.dylib "$new/lib/libMoltenVK.dylib" 2>/dev/null
bundle_dylibs "$new/lib" "$new/lib/libMoltenVK.dylib"
sed 's|"library_path": *"[^"]*"|"library_path": "../../../lib/libMoltenVK.dylib"|' \
	"$mvk/etc/vulkan/icd.d/MoltenVK_icd.json" > "$new/share/vulkan/icd.d/MoltenVK_icd.json"

rt="$new/lib/wivrn/libopenxr_wivrn.dylib"
lipo -create "$CX86/libopenxr_wivrn.dylib" "$CARM/libopenxr_wivrn.dylib" -output "$rt"
chmod u+w "$rt"
delete_rpaths "$rt"
cat > "$new/share/openxr/1/openxr_wivrn.json" <<'JSON'
{
    "file_format_version": "1.0.0",
    "runtime": {
        "name": "WiVRn",
        "library_path": "../../../lib/wivrn/libopenxr_wivrn.dylib"
    }
}
JSON

cat > "$new/bin/wivrn-server" <<'SH'
#!/bin/sh
here="$(cd "$(dirname "$0")/.." && pwd -P)"
: "${VK_DRIVER_FILES:=$here/share/vulkan/icd.d/MoltenVK_icd.json}"
export VK_DRIVER_FILES
exec "$here/libexec/wivrn/wivrn-server" "$@"
SH
chmod +x "$new/bin/wivrn-server"

cp "$SERVER/server/ipc-stamp" "$new/share/wivrn/ipc-stamp"
{
	echo "version=$(cat "$ROOT/VERSION")"
	echo "wivrn-macos=$(git -C "$ROOT" describe --always --dirty 2>/dev/null || echo unknown)"
	echo "wivrn=$(sed -n 's/^GIT_TAG:[A-Z]*=//p' "$SERVER/CMakeCache.txt") $(git -C "$ROOT/third_party/wivrn" rev-parse HEAD)"
	echo "monado-base=$(cat "$ROOT/build/monado-snapshot/.snapshot-base")"
	echo "monado-tree=$(cat "$ROOT/build/monado-snapshot/.snapshot-tree")"
	echo "wivrn-patches=$(cd "$ROOT/patches/wivrn" && ls *.patch | tr '\n' ' ' | sed 's/ $//')"
	echo "monado-patches=$(tr '\n' ' ' < "$ROOT/build/monado-snapshot/.snapshot-patches" | sed 's/ $//')"
	echo "moltenvk=$(brew list --versions molten-vk | awk '{print $2}')"
	echo "prefix=$prefix"
	echo "built=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$new/share/wivrn/build-info"

doc="$new/share/doc/wivrn-macos"
cp "$ROOT/LICENSE" "$doc/LICENSE"
cp "$ROOT/patches/LICENSE.md" "$doc/PATCHES-LICENSE.md"
cp "$ROOT/third_party/wivrn/COPYING" "$doc/COPYING.WiVRn"
cp "$ROOT/third_party/monado/LICENSE" "$doc/LICENSE.Monado"

left="$(for f in "$srv" "$rt" "$new/lib"/*.dylib; do
	otool -L "$f" | tail -n +2 | awk '{print $1}' | grep -E '^(/opt/homebrew|/usr/local)/' || true; done | sort -u)"
[[ -z "$left" ]] || die "unbundled dylibs left: $left"
[[ "$(lipo -archs "$rt")" == "x86_64 arm64" ]] || die "$rt is not universal"

codesign --force -s - "$new/lib"/*.dylib "$rt" "$srv" 2>/dev/null
rm -rf "$DEST"
mv "$new" "$DEST"
echo "==> done: $DEST ($(du -sh "$DEST" | cut -f1))"
