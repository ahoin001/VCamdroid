# VCamdroid for iOS

The iOS companion app for [VCamdroid](../../README.md). Turns an iPhone into a
low-latency virtual webcam for the Windows VCamdroid client, with full
manual camera controls (zoom across the entire built-in lens range, exposure,
white balance, focus, and stabilization).

| | |
|---|---|
| **Minimum iOS**     | 16.0  |
| **Devices**         | iPhone XS and newer (built-in triple-camera support recommended; iPhone 11 Pro / 12 Pro / 13 Pro / 14 Pro / 15 Pro / 16 Pro and Max variants) |
| **Build**           | Xcode 15 or newer |
| **Architecture**    | Protocol-oriented Swift, SwiftUI for surfaces + UIKit `AVCaptureVideoPreviewLayer` for the camera viewport |

## Build

This project uses [XcodeGen](https://github.com/yonki/XcodeGen) so the
`.xcodeproj` does not live in version control. Generate it locally:

```bash
brew install xcodegen
cd ios/VCamdroidiOS
xcodegen generate
open VCamdroidiOS.xcodeproj
```

Set the deployment target's "Signing & Capabilities" to your Apple Developer
team. Build and run on a physical device (the iOS simulator does not support
`AVCaptureSession` from a real camera).

## High-level architecture

```
SwiftUI views
     │
StreamController  ───────────  Bonjour (Phase 3)
     │
     ├── CaptureSessionManager  (AVCaptureSession + AVCaptureVideoDataOutput)
     │
     ├── VTH264Encoder          (VTCompressionSession, zero-copy from IOSurface)
     │
     ├── VideoStreamWriter      (TCP 8554, magic-prefixed, length-prefixed NALs)
     │
     ├── ControlChannel         (TCP 6969, mirrors Android binary protocol)
     │
     └── Camera controllers     (Lens / Exposure / WhiteBalance / Focus / Stabilization)
```

Every public type that participates in a side effect is fronted by a
`protocol`, which keeps the orchestrator testable and lets us swap
implementations (for example, a mock encoder in unit tests).

## Protocol compatibility

The over-the-wire format is documented in
[`docs/PROTOCOL.md`](../../docs/PROTOCOL.md). The iOS app uses **v2** of the
protocol: identical control framing as Android, with a different video
transport (raw TCP NAL units instead of RTSP).

## Tests

```bash
xcodebuild -project VCamdroidiOS.xcodeproj -scheme VCamdroidiOSTests test
```

The unit tests cover the wire-format encoders and decoders. Capture / encode
behavior must be validated on-device.
