# wivrn-macos

[![Build](https://github.com/orchardxr/wivrn-macos/actions/workflows/build.yml/badge.svg)](https://github.com/orchardxr/wivrn-macos/actions/workflows/build.yml)

Part of [orchardxr](https://github.com/orchardxr): vibe-coded support for VR on macOS: native and Windows games, on
Apple Silicon, streamed via WiVRn.

A macOS (Apple Silicon) port of the [WiVRn](https://github.com/WiVRn/WiVRn) server: stream OpenXR apps from a Mac to
any WiVRn-supported headset running the stock WiVRn client 26.9 (tested on Quest 3S). It has the server (Monado + a
VideoToolbox HEVC encoder + a Core Audio tap), and the OpenXR runtime that apps load. The runtime is a universal
(x86_64 + arm64) IPC client, so Rosetta and native apps can both use it.

The model is Linux WiVRn: the server and its runtime are installed once, and apps load the runtime through its
manifest. Native macOS OpenXR apps work through it, with Metal (`XR_KHR_metal_enable`) or Vulkan (MoltenVK); that is
barely tested so far. Windows games are supported via [orchardxr/varbor](https://github.com/orchardxr/varbor), native
Mac OpenVR games via [orchardxr/opencomposite-macos](https://github.com/orchardxr/opencomposite-macos). This code came
from orchardxr/varbor (formerly MacVR), where the port was developed; this repository has a fresh history.

## Layout

| Path | What |
|---|---|
| `third_party/wivrn` | WiVRn v26.9 (`bbc6e4cc`), submodule, matches the headset client 26.9 |
| `third_party/monado` | Monado `f037264d` (WiVRn v26.9's `monado-rev`), submodule |
| `third_party/openxr-sdk` | OpenXR-SDK-Source `release-1.1.65`, submodule: loader and hello_xr for the test programs |
| `patches/wivrn`, `patches/monado`, `patches/openxr-sdk` | Our changes to upstream, as patch series ([docs/wivrn.md](docs/wivrn.md)) |
| `patches/diag` | WiVRn diagnostic patches, for measurements only, never part of a build |
| `encoder/` | libmvt, the VideoToolbox HEVC/H.264 encoder the server uses ([docs/encoder.md](docs/encoder.md)) |
| `cmake/` | Initial cache for Monado on macOS |
| `scripts/` | Patch, build, install and run scripts |
| `tests/` | Encoder harness, OpenXR test programs (empty frames, Metal), CoreAudio test tone |
| `tools/` | Readers for the server's diagnostic dumps |
| `docs/` | The port ([wivrn.md](docs/wivrn.md)), the encoder, the Linux comparison |

## Requirements

- Apple Silicon Mac, Xcode with the current macOS SDK. Developed on macOS 27.
- Homebrew: `brew bundle` ([Brewfile](Brewfile): `cmake ninja pkg-config eigen jsoncpp molten-vk glib boost
  nlohmann-json openssl libarchive librsvg cli11 libpng x264`; x264 is optional, `WIVRN_USE_X264=OFF`). `ccache` is
  used when installed.
- [LunarG Vulkan SDK](https://vulkan.lunarg.com/sdk/home#mac) 1.4.304 installed system-wide in `/usr/local` (universal
  loader, headers, glslc). The x86_64 runtime slice needs its x86_64 slice.

## Build

```sh
git clone --recursive https://github.com/orchardxr/wivrn-macos.git
cd wivrn-macos
scripts/patches.sh apply      # reset each submodule to its pin, apply patches/<project>/* (staged)
scripts/build.sh              # openxr-sdk, server, clients (x86_64, arm64), tests, install
```

`scripts/build.sh` runs these steps, which can also be run alone (`scripts/build.sh server clients install`):

| Step | Output |
|---|---|
| `openxr-sdk` | `build/openxr-sdk`: OpenXR loader and hello_xr |
| `server` | `build/wivrn/server/wivrn-server`, built against `build/monado-snapshot` (the staged Monado tree) |
| `clients` | `build/wivrn-client-{x86_64,arm64}/client/libopenxr_wivrn.dylib` |
| `tests` | `build/tests/{xr_empty_frames,xr_metal,audio_tone}` |
| `install` | `build/install` (`WIVRN_INSTALL_DIR` overrides it) |

Every build writes an `ipc-stamp` (Monado tree, socket name, WiVRn tag; `scripts/ipc-stamp.sh`). The server and both
clients must match, and `scripts/install.sh` checks that. `scripts/patches.sh status` shows each tree's pin and patch
count; `scripts/patches.sh new <project> <name>` turns work in progress in `third_party/<project>` into the next patch.
Never commit inside `third_party/`. Logs are in `build/logs/`. Details: [docs/wivrn.md](docs/wivrn.md).

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
connection as on Linux (only from the prefix it was configured for; a moved tree runs with
`--no-manage-active-runtime`). Apps must run in the same login session as the server (Mach bootstrap service).

**WiVRn.app (planned).** The dashboard port (Qt `wivrn-dashboard`) will add `WiVRn.app` around this tree: its patch
goes into `patches/wivrn/`, the app's build into `scripts/build-app.sh` (an `app` step of `scripts/build.sh`), output
`build/WiVRn.app` with the install tree in `Contents/Resources/wivrn/`. The tree's layout stays the interface for
consumers.

## CI and releases

[.github/workflows/build.yml](.github/workflows/build.yml) builds the server, both runtime slices, the test programs
and the install tree on a hosted macOS runner (ccache, cached Homebrew and Vulkan SDK downloads), starts the server once
and uploads `wivrn-macos.zip`. Pushing a tag `v<version>` runs
[.github/workflows/release.yml](.github/workflows/release.yml): the same build, then a GitHub release with
`wivrn-macos-v<version>.zip` (notes from `docs/releases/v<version>.md` if present, else generated).

## License

- Our own code (scripts, `encoder/`, `tests/`, `tools/`, `cmake/`) is MIT, see [LICENSE](LICENSE).
- The patch series follow their upstream's license because they modify that code ([patches/LICENSE.md](patches/LICENSE.md)):
  `patches/wivrn/` and `patches/diag/` are GPL-3.0, `patches/monado/` is BSL-1.0, `patches/openxr-sdk/` is Apache-2.0.
- `third_party/` submodules keep their own licenses.
- A built install tree is the WiVRn server, so GPL-3.0 as a whole; it ships the license texts in
  `share/doc/wivrn-macos/`. The bundled Homebrew libraries and MoltenVK keep their licenses.
