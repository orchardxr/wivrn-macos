#!/usr/bin/env bash
# Bundle WiVRn.app: wivrn-dashboard + wivrn-server + a private dbus-daemon + the OpenXR runtime + Qt/KDE frameworks +
# MoltenVK, ad-hoc signed.
#   scripts/build-app.sh      after scripts/build.sh server clients install dashboard-deps dashboard
# Output: build/WiVRn.app. Version: VERSION. Log: build/logs/wivrn-app.log
#
# WiVRn.app/Contents/
#   MacOS/{wivrn-dashboard,wivrn-server,dbus-daemon}
#   Frameworks/                          Qt, KDE, Homebrew dylibs, libMoltenVK, libopenxr_wivrn.dylib (universal)
#   Resources/openxr/1/openxr_wivrn.json the runtime manifest (the server sets it active on connection)
#   Resources/vulkan/icd.d/MoltenVK_icd.json
#   Resources/wivrn/{ipc-stamp,build-info}
#   Resources/AppIcon.icns               from third_party/wivrn/images/wivrn.svg
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Only the repo, Homebrew and the system: macdeployqt looks its tools up through PATH and must not stat user folders
# (cloud mounts ask for access).
export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
cd "$ROOT"
source "$ROOT/scripts/lib/bundle-dylibs.sh"
SERVER="${WIVRN_BUILD_DIR:-$ROOT/build/wivrn}/server/wivrn-server"
DASH="${WIVRN_DASHBOARD_BUILD_DIR:-$ROOT/build/wivrn-dashboard}/server/wivrn-dashboard.app"
INSTALL="${WIVRN_INSTALL_DIR:-$ROOT/build/install}"
KDE="$ROOT/build/kde/prefix"
LOG="$ROOT/build/logs/wivrn-app.log"
VERSION="$(cat "$ROOT/VERSION")"
mkdir -p "$ROOT/build/logs"
for f in "$SERVER" "$DASH" "$INSTALL/lib/wivrn/libopenxr_wivrn.dylib" "$INSTALL/share/wivrn/ipc-stamp"; do
	[[ -e "$f" ]] || { echo "build-app.sh: missing $f (scripts/build.sh)" >&2; exit 1; }
done
cmp -s "${SERVER%/*}/ipc-stamp" "$INSTALL/share/wivrn/ipc-stamp" \
	|| { echo "build-app.sh: the install tree's runtime is from another server build (scripts/build.sh install)" >&2; exit 1; }

app="$ROOT/build/WiVRn.app"
rm -rf "$app.new"
cp -R "$DASH" "$app.new"
c="$app.new/Contents"
fw="$c/Frameworks"
mkdir -p "$fw" "$c/PlugIns/kiconthemes6/iconengines" "$c/Resources/vulkan/icd.d" "$c/Resources/openxr/1" \
	"$c/Resources/wivrn"

plist="$c/Info.plist"
plutil -replace CFBundleName -string WiVRn "$plist"
plutil -replace CFBundleDisplayName -string WiVRn "$plist"
plutil -replace CFBundleIdentifier -string io.github.orchardxr.wivrn "$plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$plist"
plutil -replace CFBundleVersion -string "$VERSION" "$plist"
plutil -replace LSMinimumSystemVersion -string 14.2 "$plist"
plutil -replace NSHighResolutionCapable -bool true "$plist"
# Menu-bar only: macOS 26+ shows a status-item menu over another app's full-screen Space only for LSUIElement apps
plutil -replace LSUIElement -bool true "$plist"
plutil -replace NSAudioCaptureUsageDescription -string "WiVRn streams the game's audio to the headset." "$plist"

# App icon from WiVRn's artwork, inset to the macOS icon grid (824 of 1024)
echo "==> icon"
iconset="$ROOT/build/AppIcon.iconset"
rm -rf "$iconset"
mkdir -p "$iconset"
for s in 16 32 128 256 512; do
	for scale in 1 2; do
		suffix="" px=$((s * scale))
		[[ $scale == 1 ]] || suffix=@2x
		art=$((px * 824 / 1024))
		rsvg-convert -w "$art" -h "$art" --page-width "$px" --page-height "$px" --left $(((px - art) / 2)) \
			--top $(((px - art) / 2)) "$ROOT/third_party/wivrn/images/wivrn.svg" -o "$iconset/icon_${s}x${s}$suffix.png"
	done
done
iconutil -c icns "$iconset" -o "$c/Resources/AppIcon.icns"
plutil -replace CFBundleIconFile -string AppIcon "$plist"

cp "$SERVER" "$c/MacOS/wivrn-server"
cp -L /opt/homebrew/opt/dbus/bin/dbus-daemon "$c/MacOS/dbus-daemon"
cp "$KDE/lib/plugins/kiconthemes6/iconengines/KIconEnginePlugin.so" "$c/PlugIns/kiconthemes6/iconengines/"
chmod u+w "$c/MacOS/"*

echo "==> macdeployqt"
env -i HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" PATH="$PATH" LANG=en_US.UTF-8 \
	/opt/homebrew/bin/macdeployqt "$app.new" -always-overwrite -qmldir="$ROOT/third_party/wivrn/dashboard/qml" -qmlimport="$KDE/lib/qml" \
	-libpath="$KDE/lib" -executable="$c/PlugIns/kiconthemes6/iconengines/KIconEnginePlugin.so" > "$LOG" 2>&1 \
	|| { tail -20 "$LOG"; exit 1; }
before="$(du -sh "$app.new" | cut -f1)"

machos() {
	find "$c/MacOS" "$fw" "$c/PlugIns" "$c/Resources/qml" -type f \
		\( -perm -u+x -o -name '*.dylib' -o -name '*.so' -o -path '*.framework/Versions/*' ! -path '*/Resources/*' \) \
		-exec sh -c 'file -b "$1" | grep -q Mach-O && echo "$1"' _ {} \;
}

# macdeployqt does not follow every link of the libs it copies (an @rpath or absolute Homebrew dep of a dep). Before
# the trim, so that trimmed libs still linked fail the check below instead of coming back.
echo "==> bundle the links macdeployqt left"
files=()
while IFS= read -r f; do files+=("$f"); done < <(machos)
bundle_dylibs "$fw" "${files[@]}"

# macdeployqt deploys every plugin of the Qt modules it finds (Qt3D and Multimedia through QtQuick's scene plugins, Pdf
# through the image formats, the virtual keyboard through the input contexts). Remove the unused ones; the check below
# fails if anything left links them.
echo "==> trim"
shopt -s nullglob
for f in "$fw"/Qt{3D,Multimedia,SpatialAudio,Pdf,Quick3D,WebEngine,WebChannel,WebSockets,WebView,Positioning,Location}*.framework \
	"$fw"/Qt{Sensors,Charts,Graphs,DataVisualization,VirtualKeyboard,HunspellInputMethod,TextToSpeech,Scxml}*.framework \
	"$fw"/Qt{RemoteObjects,SerialPort,Bluetooth,Nfc,Sql,Test,QuickTest,ShaderTools,Lottie,HttpServer}*.framework \
	"$fw"/libassimp*.dylib "$fw"/libhunspell*.dylib; do
	rm -rf "$f"
done
shopt -u nullglob
rm -rf "$c/PlugIns/"{sceneparsers,geometryloaders,renderers,renderplugins,multimedia,sqldrivers,position,sensors} \
	"$c/PlugIns/"{texttospeech,virtualkeyboard,platforminputcontexts,assetimporters,qmltooling,help,printsupport,canbus}
rm -f "$c/PlugIns/imageformats/libqpdf.dylib"
for q in Qt3D QtMultimedia QtQuick3D QtWebEngine QtWebChannel QtWebSockets QtWebView QtPositioning QtLocation \
	QtSensors QtCharts QtGraphs QtDataVisualization QtVirtualKeyboard QtTextToSpeech QtScxml QtRemoteObjects \
	QtTest QtQuick/Pdf QtQuick/Scene2D QtQuick/Scene3D QtQuick/VirtualKeyboard; do
	rm -rf "$c/Resources/qml/$q"
done
find "$c" -name '*.dSYM' -prune -exec rm -rf {} +

echo "==> server, dbus-daemon, MoltenVK, OpenXR runtime"
for f in "$c/MacOS/wivrn-server" "$c/MacOS/dbus-daemon"; do
	install_name_tool -delete_rpath /usr/local/lib "$f" 2>/dev/null || true
	otool -l "$f" | grep -q "path @executable_path/../Frameworks " || install_name_tool -add_rpath @executable_path/../Frameworks "$f"
done
mvk="$(brew --prefix molten-vk)"
cp -L "$mvk/lib/libMoltenVK.dylib" "$fw/"
chmod u+w "$fw/libMoltenVK.dylib"
install_name_tool -id @rpath/libMoltenVK.dylib "$fw/libMoltenVK.dylib"
bundle_dylibs "$fw" "$c/MacOS/wivrn-server" "$c/MacOS/dbus-daemon" "$fw/libMoltenVK.dylib"
sed 's|"library_path": *"[^"]*"|"library_path": "../../../Frameworks/libMoltenVK.dylib"|' \
	"$mvk/etc/vulkan/icd.d/MoltenVK_icd.json" > "$c/Resources/vulkan/icd.d/MoltenVK_icd.json"
cp "$INSTALL/lib/wivrn/libopenxr_wivrn.dylib" "$fw/"
sed 's|"library_path": *"[^"]*"|"library_path": "../../../Frameworks/libopenxr_wivrn.dylib"|' \
	"$INSTALL/share/openxr/1/openxr_wivrn.json" > "$c/Resources/openxr/1/openxr_wivrn.json"
cp "$INSTALL/share/wivrn/ipc-stamp" "$INSTALL/share/wivrn/build-info" "$c/Resources/wivrn/"
cp -R "$INSTALL/share/doc/wivrn-macos" "$c/Resources/licenses"
echo "app=$VERSION" >> "$c/Resources/wivrn/build-info"
sed -i '' '/^prefix=/d' "$c/Resources/wivrn/build-info"

links="$(machos | while IFS= read -r f; do otool -L "$f" | grep -v ':$' | awk -v f="${f#"$c/"}" '{print $1, f}'; done)"
deps="$(cut -d' ' -f1 <<< "$links" | sort -u)"
left="$(grep -E "^(/opt/homebrew|/usr/local|$ROOT)/" <<< "$links" || true)"
[[ -z "$left" ]] || { echo "unbundled dylibs left (dep, linked from):"; echo "$left"; exit 1; }
missing="$(grep '^@rpath/' <<< "$deps" | while read -r d; do
	n="${d#@rpath/}"
	[[ -e "$fw/$n" ]] || echo "$d"
done)"
[[ -z "$missing" ]] || { echo "trimmed too much, still linked:"; echo "$missing"; exit 1; }
rpaths="$(machos | while IFS= read -r f; do
	otool -l "$f" | awk -v f="${f#"$c/"}" '/LC_RPATH/ { r = 1 } r && $1 == "path" { if ($2 !~ /^@/) print $2, f; r = 0 }'
done)"
[[ -z "$rpaths" ]] || { echo "absolute rpaths left (rpath, in):"; echo "$rpaths"; exit 1; }

echo "==> sign"
codesign --force --deep -s - "$app.new" >> "$LOG" 2>&1
codesign --verify --deep --strict "$app.new"
rm -rf "$app"
mv "$app.new" "$app"
echo "==> done: $app (after macdeployqt $before, trimmed $(du -sh "$app" | cut -f1))"
