<p align="center"><img src="docs/icon.png" width="128" alt=""></p>

# Rodinia

A native macOS VPN client for VLESS + Reality, built with SwiftUI and Xray-core.

<p align="center">
  <a href="https://github.com/zachgree/rodinia-client/releases/latest/download/Rodinia.dmg"><img src="https://img.shields.io/badge/Download_for_Mac-Rodinia.dmg-3D5A80?style=for-the-badge&logo=apple&logoColor=white" alt="Download Rodinia for Mac"></a>
</p>
<p align="center"><sub>macOS 15 or later · Apple Silicon and Intel · signed and notarized by Apple</sub></p>

### Install

1. Download **Rodinia.dmg** and open it.
2. Drag **Rodinia** into **Applications**, then open it from there.
3. Paste your subscription link.
4. The first time you connect, macOS asks for two permissions:
   - Allow Rodinia in **System Settings → General → Login Items & Extensions → Network Extensions**.
   - Choose **Allow** when it asks to add a VPN configuration.

Rodinia was the supercontinent that joined every landmass about a billion years ago. The app takes its look from that: while you're disconnected, the map sits in pieces. Click it and the plates drift together. Once the tunnel is up, they fuse into one continent.

<p align="center">
  <img src="docs/disconnected.png" width="300" alt="Rodinia, not connected">
  <img src="docs/connected.png" width="300" alt="Rodinia, connected to the United Kingdom">
</p>

## What it does

- Works with any standard subscription link: a base64 list of `vless://` links, the format 3X-UI, Marzban and most panels serve
- Reads `Profile-Title`, `Profile-Update-Interval` and `Subscription-Userinfo`, so you see your plan, renewal date and provider name
- Live latency for each location, plus throughput and session time while you're connected
- Sends all traffic through the tunnel, DNS and UDP included. Local network traffic stays local
- Menu bar control, ⌘K to connect, ⌘1–9 to switch location
- Light and dark mode both designed, and every animation respects Reduce Motion

## How it works

| Part | What it is |
|---|---|
| `App/` | SwiftUI app: window, menu bar extra, onboarding |
| `Tunnel/` | Packet tunnel provider, shipped as a system extension |
| `Packages/RodiniaKit/` | Link parsing, subscriptions, Xray config generation. Shared with the future iOS app |
| `Core/` | A small Go bridge to [Xray-core](https://github.com/XTLS/Xray-core), built with gomobile into `RodiniaCore.xcframework` |

The tunnel hands NetworkExtension's utun file descriptor straight to Xray's TUN inbound (`xray.tun.fd`), so packets go from the kernel to Xray with no tun2socks layer in between.

## Building

Requirements: macOS 15+, Xcode 26, Go, [XcodeGen](https://github.com/yonaskolb/XcodeGen) and an Apple Developer account. A packet tunnel can't be signed without one.

```sh
brew install go xcodegen
cp Config/Local.xcconfig.example Config/Local.xcconfig   # add your team ID and bundle prefix
scripts/build-core.sh                                    # builds Xray-core (first run takes a few minutes)
xcodegen generate
open Rodinia.xcodeproj
```

macOS only loads system extensions from apps in `/Applications`. Build, copy `Rodinia.app` there and open it from there. The first time you connect, macOS asks you to allow the extension in System Settings and to allow the VPN configuration.

Run the RodiniaKit tests with `swift test --package-path Packages/RodiniaKit`.

### Design snapshots

Debug builds can render every screen to PNG without a working tunnel:

```sh
Rodinia.app/Contents/MacOS/Rodinia -snapshots /tmp/rodinia-snaps
```

## Releasing

`scripts/release.sh` builds a universal app, signs it with Developer ID, and notarizes and staples both the app and the `.dmg`. It needs a one-time `xcrun notarytool store-credentials rodinia-notary`. Then publish it:

```sh
gh release create v0.2.0 dist/Rodinia.dmg --title "Rodinia 0.2.0"
```

Every release keeps the file name `Rodinia.dmg`, so the download button always gets the latest version.

## License

[Mozilla Public License 2.0](LICENSE), the same as Xray-core.
