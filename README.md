# wivrn-macos

[![Build](https://github.com/orchardxr/wivrn-macos/actions/workflows/build.yml/badge.svg)](https://github.com/orchardxr/wivrn-macos/actions/workflows/build.yml)

Part of [orchardxr](https://github.com/orchardxr): vibe-coded support for VR on macOS: native and Windows games, on
Apple Silicon, streamed via WiVRn.

The [WiVRn](https://github.com/WiVRn/WiVRn) streaming server for macOS: it streams OpenXR apps from your Mac to a
headset running the stock WiVRn app. It includes the server (hardware HEVC encoding with VideoToolbox, game audio
through a Core Audio tap) and the OpenXR runtime that apps load. As on Linux, you install the server once, and apps
find WiVRn through its runtime manifest.

## What works

- Any WiVRn-supported headset with the WiVRn client 26.9 (tested on Quest 3S).
- Native macOS OpenXR apps, with Metal (`XR_KHR_metal_enable`) or Vulkan (MoltenVK). Barely tested so far.
- Apps built for Apple Silicon and Intel (Rosetta): the runtime is universal.
- Windows games, via [orchardxr/varbor](https://github.com/orchardxr/varbor). Native Mac OpenVR games, via
  [orchardxr/opencomposite-macos](https://github.com/orchardxr/opencomposite-macos).

## Requirements

- An Apple Silicon Mac with macOS 14.2 or newer (developed on macOS 27).
- A headset with the WiVRn app 26.9, on the same network as the Mac (5 GHz Wi-Fi or better; Ethernet for the Mac
  helps).
- Nothing else: the release bundles its libraries and MoltenVK.

## Install

Download `WiVRn-<version>.zip` from [Releases](https://github.com/orchardxr/wivrn-macos/releases), unzip it and drag
`WiVRn.app` to `/Applications`. It is ad-hoc signed (not notarized): the first time, right-click it and choose Open,
or run `xattr -dr com.apple.quarantine /Applications/WiVRn.app`. WiVRn.app updates itself from the releases ("Check for
updates" in its menu; it also checks at startup).

Without the dashboard: `wivrn-macos-<version>.zip` from the same release has the server and the runtime only, as a
folder you can put anywhere (`bin/wivrn-server`).

## Usage

1. Open WiVRn.app. It starts the server, which announces itself on the network (Bonjour).
2. Open WiVRn on the headset and pick your Mac. The first time, enter the PIN that WiVRn.app shows (Headsets → pair
   for another headset later).
3. Start your OpenXR app. Once a headset is connected, WiVRn sets itself as the active OpenXR runtime, as on Linux;
   or select it for one app with
   `XR_RUNTIME_JSON=/Applications/WiVRn.app/Contents/Resources/openxr/1/openxr_wivrn.json`.
   Start apps from the same login session as WiVRn (not over ssh).
4. Quitting WiVRn.app stops the server.

On first use with audio, macOS asks to let WiVRn record system audio (Privacy & Security, Screen & System Audio
Recording). Without it the headset gets silence. Settings, environment variables and logs are described in
[docs/wivrn.md](docs/wivrn.md).

## Limitations

- The dashboard is new on macOS: its USB (adb) connection and headset app install pages are untested, and it still
  shows some Linux-only hints (Steam launch options). No `wivrnctl`.
- Not notarized: macOS asks for confirmation on first launch.
- No microphone from the headset, no input forwarding.
- Only HEVC/H.264 through VideoToolbox; no AV1 encoding.
- Native macOS app support is new and barely tested.

## License

- Our own code (scripts, `encoder/`, `tests/`, `tools/`, `cmake/`) is MIT, see [LICENSE](LICENSE).
- The patch series follow their upstream's license because they modify that code ([patches/LICENSE.md](patches/LICENSE.md)):
  `patches/wivrn/` and `patches/diag/` are GPL-3.0, `patches/monado/` is BSL-1.0, `patches/openxr-sdk/` is Apache-2.0.
- `third_party/` submodules keep their own licenses.
- A release is WiVRn, so GPL-3.0 as a whole; the install tree ships the license texts in `share/doc/wivrn-macos/`.
  WiVRn.app bundles Qt (LGPL-3.0), KDE Frameworks (LGPL), D-Bus (AFL-2.1/GPL-2.0), Homebrew libraries and MoltenVK,
  each under its own license.

## Development

Building from source, the repository layout, the install tree, the patch workflow, CI and releases:
[docs/development.md](docs/development.md). This code came from orchardxr/varbor, where the port was
developed; this repository has a fresh history.
