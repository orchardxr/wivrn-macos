# Development

How wivrn-macos is laid out, built, patched and released. The port itself is described in [wivrn.md](wivrn.md), the
encoder in [encoder.md](encoder.md).

## Layout

| Path | What |
|---|---|
| `third_party/wivrn` | WiVRn v26.9 (`bbc6e4cc`), submodule, matches the headset client 26.9 |
| `third_party/monado` | Monado `f037264d` (WiVRn v26.9's `monado-rev`), submodule |
| `third_party/openxr-sdk` | OpenXR-SDK-Source `release-1.1.65`, submodule: loader and hello_xr for the test programs |
| `patches/wivrn`, `patches/monado`, `patches/openxr-sdk` | Our changes to upstream, as patch series ([docs/wivrn.md](wivrn.md)) |
| `patches/diag` | WiVRn diagnostic patches, for measurements only, never part of a build |
| `encoder/` | libmvt, the VideoToolbox HEVC/H.264 encoder the server uses ([docs/encoder.md](encoder.md)) |
| `cmake/` | Initial cache for Monado on macOS |
| `scripts/` | Patch, build, install and run scripts |
| `tests/` | Encoder harness, OpenXR test programs (empty frames, Metal), CoreAudio test tone |
| `tools/` | Readers for the server's diagnostic dumps |
| `docs/` | The port ([wivrn.md](wivrn.md)), the encoder, the Linux comparison, this file |

## Build requirements

- Apple Silicon Mac, Xcode with the current macOS SDK. Developed on macOS 27.
- Homebrew: `brew bundle` ([Brewfile](../Brewfile): `cmake ninja pkg-config eigen jsoncpp molten-vk glib boost
  nlohmann-json openssl libarchive librsvg cli11 libpng x264`; x264 is optional, `WIVRN_USE_X264=OFF`). `ccache` is
  used when installed.
- For the dashboard, also from the Brewfile: `qt dbus extra-cmake-modules ki18n karchive gettext`.
- [LunarG Vulkan SDK](https://vulkan.lunarg.com/sdk/home#mac) 1.4.304 installed system-wide in `/usr/local` (universal
  loader, headers, glslc). The x86_64 runtime slice needs its x86_64 slice.

## Build

```sh
git clone --recursive https://github.com/orchardxr/wivrn-macos.git
cd wivrn-macos
scripts/patches.sh apply      # reset each submodule to its pin, apply patches/<project>/* (staged)
scripts/build.sh              # server, runtime, install tree, dashboard and WiVRn.app
```

`scripts/build.sh` runs these steps, which can also be run alone (`scripts/build.sh server clients install`):

| Step | Output |
|---|---|
| `openxr-sdk` | `build/openxr-sdk`: OpenXR loader and hello_xr |
| `server` | `build/wivrn/server/wivrn-server`, built against `build/monado-snapshot` (the staged Monado tree) |
| `clients` | `build/wivrn-client-{x86_64,arm64}/client/libopenxr_wivrn.dylib` |
| `tests` | `build/tests/{xr_empty_frames,xr_metal,audio_tone}` |
| `install` | `build/install` (`WIVRN_INSTALL_DIR` overrides it) |
| `dashboard-deps` | `build/kde/prefix`: the KDE frameworks Homebrew lacks (skipped once built) |
| `dashboard` | `build/wivrn-dashboard/server/wivrn-dashboard.app` (dev build) |
| `app` | `build/WiVRn.app` |

Every build writes an `ipc-stamp` (Monado tree, socket name, WiVRn tag; `scripts/ipc-stamp.sh`). The server and both
clients must match, and `scripts/install.sh` checks that. `scripts/patches.sh status` shows each tree's pin and patch
count; `scripts/patches.sh new <project> <name>` turns work in progress in `third_party/<project>` into the next patch.
Never commit inside `third_party/`. Logs are in `build/logs/`. Details: [wivrn.md](wivrn.md).

## Install layout

```
build/install/
├── bin/wivrn-server                      launcher: sets VK_DRIVER_FILES to the bundled MoltenVK, execs the server
├── libexec/wivrn/wivrn-server            the server (arm64)
├── lib/*.dylib                           Homebrew and Vulkan loader dylibs, libMoltenVK (@rpath)
├── lib/wivrn/libopenxr_wivrn.dylib       the OpenXR runtime, universal (x86_64 arm64), IPC client only
├── share/openxr/1/openxr_wivrn.json      runtime manifest, library_path relative to it
├── share/vulkan/icd.d/MoltenVK_icd.json  ICD manifest of the bundled MoltenVK
├── share/wivrn/ipc-stamp                 IPC stamp of the server (= both runtime slices)
├── share/wivrn/build-info                versions: this repo, WiVRn tag, Monado base and tree, patch lists, prefix
└── share/doc/wivrn-macos/                licenses
```

The tree needs no Homebrew or Vulkan SDK at run time and is ad-hoc signed. Run the server with
`build/install/bin/wivrn-server` (`--pairing` prints a PIN for a new headset); point apps at the runtime with
`XR_RUNTIME_JSON=build/install/share/openxr/1/openxr_wivrn.json`, or let the server set the active runtime on
connection as on Linux (it finds the manifest relative to itself, WiVRn patch 0013, so a moved tree works). Apps must
run in the same login session as the server (Mach bootstrap service).

## WiVRn.app

WiVRn's own Qt 6 / Kirigami dashboard (`third_party/wivrn/dashboard`, patches 0012 and 0014; what they change:
[wivrn.md](wivrn.md)) with the server, a private `dbus-daemon` and the OpenXR runtime:

```
WiVRn.app/Contents/
├── MacOS/{wivrn-dashboard,wivrn-server,dbus-daemon}
├── Frameworks/                          Qt, KDE, Homebrew dylibs, libMoltenVK, libopenxr_wivrn.dylib (universal)
├── PlugIns/, Resources/qml/             Qt plugins and QML modules (macdeployqt)
├── Resources/openxr/1/openxr_wivrn.json the runtime manifest
├── Resources/vulkan/icd.d/MoltenVK_icd.json
└── Resources/wivrn/{ipc-stamp,build-info}, Resources/licenses/
```

- Dependencies (arm64, Xcode clang): Homebrew `qt` 6.12, `dbus` 1.16, `extra-cmake-modules`, `ki18n`, `karchive`
  6.31, `gettext`. Not in Homebrew, built by `scripts/build-dashboard-deps.sh` into `build/kde/prefix` (~3 min, 11
  CMake projects): KF 6.31.0 kcoreaddons, kconfig, kguiaddons, kcolorscheme, kwidgetsaddons, breeze-icons
  (`ICONS_LIBRARY=ON`: icons compiled into libKF6BreezeIcons, which KIconThemes uses on macOS), kiconthemes,
  kirigami, kcrash (for kirigami-addons), kirigami-addons 1.16.0, QCoro 0.13.0. qqc2-desktop-style is skipped (Linux
  look; Fusion instead).
- `scripts/run-dashboard.sh [server args]` runs the dev build with `build/wivrn`'s server. Don't run it next to
  another wivrn-server (port 9757, the `comp_ipc` socket); for a side-by-side test use scratch `XDG_CONFIG_HOME`
  (with `wivrn/config.json` `{"port": 9758}`) and `XDG_RUNTIME_DIR`, and `--no-publish-service`.
- `scripts/build-app.sh` copies the dev bundle, sets the Info.plist (bundle id `io.github.orchardxr.wivrn`, version
  from `VERSION`), runs macdeployqt (slow: it scans the QML imports), removes the Qt modules macdeployqt deploys but
  nothing uses (Qt3D, Multimedia, Pdf, Quick3D, WebEngine, Positioning, ... and their plugins and QML modules; it then
  checks that no Mach-O in the bundle links a missing `@rpath` library), bundles the server's and dbus-daemon's
  Homebrew dylibs and MoltenVK, and signs ad hoc (`codesign --deep`). Size: 201 MB after macdeployqt (before the
  server and its libraries are added), 186 MB finished, 80 MB zipped. macdeployqt takes ~15 min.
- Version: `VERSION` is `<WiVRn major>.<WiVRn minor>.<wivrn-macos revision>`, the release tag is `v` + it, and
  the app's self-update compares it with the latest release.
- Notarization would need a Developer ID and the hardened runtime (`codesign -o runtime`, entitlements for audio
  capture).

## CI and releases

[.github/workflows/build.yml](../.github/workflows/build.yml) builds the server, both runtime slices, the test programs,
the install tree, the dashboard and WiVRn.app on a hosted macOS runner (ccache; cached Homebrew and Vulkan SDK
downloads; `build/kde/prefix` cached on the deps script and the Homebrew Qt version), starts the server once and
uploads `wivrn-macos.zip` and `WiVRn.zip`.

To release: bump `VERSION`, optionally add notes as `docs/releases/v<version>.md` (else GitHub generates them),
commit, push a tag `v<version>`. [.github/workflows/release.yml](../.github/workflows/release.yml) runs the same build,
checks the tag against `VERSION` and publishes `WiVRn-<version>.zip` (what WiVRn.app's self-update downloads) and
`wivrn-macos-<version>.zip` (the install tree).
