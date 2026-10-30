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

Download `wivrn-macos-<version>.zip` from [Releases](https://github.com/orchardxr/wivrn-macos/releases) and unzip
it wherever you like, for example to `~/Applications/wivrn-macos`. It is ad-hoc signed; if macOS blocks it, run
`xattr -dr com.apple.quarantine ~/Applications/wivrn-macos`.

WiVRn.app, with the WiVRn dashboard, is planned. Once it exists, installing will be: drag it to `/Applications`.

## Usage

1. Start the server: `~/Applications/wivrn-macos/bin/wivrn-server`. It announces itself on the network (Bonjour).
2. Open WiVRn on the headset and pick your Mac. The first time, enter the PIN that the server prints (to pair
   another headset later, start the server with `--pairing`).
3. Start the OpenXR app with the runtime selected:
   ```sh
   XR_RUNTIME_JSON=~/Applications/wivrn-macos/share/openxr/1/openxr_wivrn.json ./your-openxr-app
   ```
   Start the app from the same login session as the server (not over ssh).
4. Ctrl-C stops the server.

On first use with audio, macOS asks to let the terminal record system audio (Privacy & Security, Screen & System
Audio Recording). Without it the headset gets silence. Settings, environment variables and logs are described in
[docs/wivrn.md](docs/wivrn.md).

## Limitations

- No dashboard or `wivrnctl` yet: pairing and settings go through the terminal and `~/.config/wivrn/config.json`.
- No microphone from the headset, no input forwarding.
- The server only sets itself as the system's active OpenXR runtime when run from the folder it was built for. A
  release zip doesn't do that, so set `XR_RUNTIME_JSON` as above.
- Only HEVC/H.264 through VideoToolbox; no AV1 encoding.
- Native macOS app support is new and barely tested.

## License

- Our own code (scripts, `encoder/`, `tests/`, `tools/`, `cmake/`) is MIT, see [LICENSE](LICENSE).
- The patch series follow their upstream's license because they modify that code ([patches/LICENSE.md](patches/LICENSE.md)):
  `patches/wivrn/` and `patches/diag/` are GPL-3.0, `patches/monado/` is BSL-1.0, `patches/openxr-sdk/` is Apache-2.0.
- `third_party/` submodules keep their own licenses.
- A release is the WiVRn server, so GPL-3.0 as a whole; it ships the license texts in `share/doc/wivrn-macos/`. The
  bundled Homebrew libraries and MoltenVK keep their licenses.

## Development

Building from source, the repository layout, the install tree, the patch workflow, CI and releases:
[docs/development.md](docs/development.md). This code came from orchardxr/varbor (formerly MacVR), where the port was
developed; this repository has a fresh history.
