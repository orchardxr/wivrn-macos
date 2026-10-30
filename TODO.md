# TODO

## USB (adb reverse): first session drops at FOCUSED (2026-10-30)

Seen once with WiVRn.app and a Quest 3S on USB, first connect after the dashboard started the server; a retry worked.
Server log (the dashboard's, 20:49):

```
20:49:22.279 WiVRn 26.9 starting
20:49:24.590 Service published
20:49:44.848 Client connected                    (22 s after start; handshake and session setup fine)
20:49:45.7   videotoolbox streams 0-2 created, zero-copy
20:49:51.600 CoreAudio speaker: process tap
20:49:51.601 Session state changed: XR_SESSION_STATE_FOCUSED
20:49:51.601 WARN [run_net] Network exception: Error on control socket, Session paused.
20:49:51.629 WARN Error loading icon .../546560/library_600x900.jpg: Broken pipe
```

- Not an early TCP connection being rejected: the connection was accepted, PIN/encryption and the session went
  through, then the control socket got POLLHUP/POLLERR 7 s later. The client shows "Socket shutdown" (recv 0).
- The drop coincides with the headset's application list: at FOCUSED the server sends the list and one PNG icon
  (~0.1-0.5 MB) per app over the TCP control socket; that send then fails with EPIPE, so the peer (adb's tunnel or the
  client) had reset the connection.
- Still unexplained: what makes adb's reverse tunnel or the client drop it. Next time: `adb logcat` of the client and
  adbd around the drop, `~/Library/Logs/WiVRn/wivrn-server.log`, and whether it happens without the app list
  (no Steam VR apps) or on Wi-Fi.
- Possibly related, fixed in WiVRn patch 0015: accepted headset sockets were not close-on-exec (upstream set
  `FD_CLOEXEC` on the listener instead of the accepted fd), so `caffeinate` and the server's execv after a session kept
  old connections open.

## Other

- Dashboard on macOS: USB connect and APK install pages untried with a headset; Linux-only hints (Steam launch
  options) still shown.
- macdeployqt takes ~15 min (install_name_tool/otool/strip per binary); WiVRn.app is 186 MB, mostly Qt and ICU.
- Notarization: Developer ID, hardened runtime, audio capture entitlement.
