#!/usr/bin/env bash
# Build the KDE pieces wivrn-dashboard needs that Homebrew lacks, into build/kde/prefix.
#   scripts/build-dashboard-deps.sh [name...]     default: all, in dependency order
# Homebrew: qt dbus extra-cmake-modules ki18n karchive gettext (KF 6.31.0 to match the tags below).
# Logs: build/logs/kde-<name>-{configure,build}.log
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib/ccache.sh"
KDE="$ROOT/build/kde"
PREFIX="$KDE/prefix"
LOGS="$ROOT/build/logs"
mkdir -p "$KDE/src" "$KDE/build" "$LOGS"

KF=v6.31.0
deps=(
	"kcoreaddons https://invent.kde.org/frameworks/kcoreaddons.git $KF -DBUILD_PYTHON_BINDINGS=OFF"
	"kconfig https://invent.kde.org/frameworks/kconfig.git $KF -DBUILD_PYTHON_BINDINGS=OFF"
	"kguiaddons https://invent.kde.org/frameworks/kguiaddons.git $KF -DBUILD_PYTHON_BINDINGS=OFF -DWITH_WAYLAND=OFF -DWITH_X11=OFF"
	"kcolorscheme https://invent.kde.org/frameworks/kcolorscheme.git $KF"
	"kwidgetsaddons https://invent.kde.org/frameworks/kwidgetsaddons.git $KF -DBUILD_PYTHON_BINDINGS=OFF"
	"breeze-icons https://invent.kde.org/frameworks/breeze-icons.git $KF -DICONS_LIBRARY=ON -DSKIP_INSTALL_ICONS=ON -DWITH_ICON_GENERATION=OFF"
	"kiconthemes https://invent.kde.org/frameworks/kiconthemes.git $KF -DKICONTHEMES_USE_QTQUICK=ON"
	"kirigami https://invent.kde.org/frameworks/kirigami.git $KF"
	"kcrash https://invent.kde.org/frameworks/kcrash.git $KF -DWITH_X11=OFF"
	"kirigami-addons https://invent.kde.org/libraries/kirigami-addons.git v1.16.0"
	"qcoro https://github.com/qcoro/qcoro.git v0.13.0 -DQCORO_BUILD_EXAMPLES=OFF -DQCORO_WITH_QTWEBSOCKETS=OFF -DQCORO_WITH_QTDBUS=ON"
)

want=("$@")
for d in "${deps[@]}"; do
	read -r name url tag opts <<< "$d"
	if (( ${#want[@]} )) && [[ " ${want[*]} " != *" $name "* ]]; then continue; fi
	src="$KDE/src/$name"
	if [[ ! -d "$src/.git" ]]; then
		echo "==> clone $name $tag"
		git -c advice.detachedHead=false clone -q --depth 1 --branch "$tag" "$url" "$src"
	fi
	echo "==> build $name"
	# shellcheck disable=SC2086
	cmake -S "$src" -B "$KDE/build/$name" -G Ninja \
		-DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" \
		-DCMAKE_PREFIX_PATH="$PREFIX;/opt/homebrew/opt/qt;/opt/homebrew" \
		-DBUILD_TESTING=OFF -DBUILD_QCH=OFF -DBUILD_WITH_QML=ON -DKDE_INSTALL_USE_QT_SYS_PATHS=OFF \
		-DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 $opts \
		> "$LOGS/kde-$name-configure.log" 2>&1 || { tail -30 "$LOGS/kde-$name-configure.log"; exit 1; }
	ninja -C "$KDE/build/$name" install > "$LOGS/kde-$name-build.log" 2>&1 \
		|| { grep -E -A3 "error|FAILED" "$LOGS/kde-$name-build.log" | head -40; exit 1; }
done
echo "==> done: $PREFIX"
