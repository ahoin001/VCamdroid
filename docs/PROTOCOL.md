# VCamdroid Wire Protocol

This document is the canonical reference for every byte on the wire between a
phone (Android or iOS) and the Windows client. It exists so that contributors
on either platform can implement, verify, and extend the protocol without
ambiguity.

> **Status:** v2. v1 was the original Android-only protocol. v2 is backwards
> compatible: existing Android builds keep working unchanged. iOS uses v2 and
> announces itself via a `deviceType` field.

---

## Transports

| Channel        | Port  | Direction         | Carrier      |
|----------------|-------|-------------------|--------------|
| Control        | 6969  | Phone → Windows   | TCP          |
| Control        | 6969  | Windows → Phone   | TCP          |
| Video (Android)| 8554  | Phone → Windows   | RTSP/RTP     |
| Video (iOS)    | 8554  | Phone → Windows   | Raw TCP (NAL framed) |

USB tunneling per platform:

- **Android:** `adb reverse tcp:6969 tcp:6969` + `adb forward tcp:8554 tcp:8554`
  (the Android app advertises an RTSP URL containing `127.0.0.1` so the Windows
  side forces RTSP-over-TCP transport).
- **iOS:** `libusbmuxd` tunnel over the Apple Mobile Device Service
  (`com.apple.mobile.lockdown`). The Windows side allocates two local TCP
  endpoints that forward into the device's `localhost:6969` and
  `localhost:8554` sockets.

---

## Endianness

The original Android implementation has two distinct conventions:

| Direction          | Endianness | Examples                          |
|--------------------|------------|-----------------------------------|
| Phone → Windows    | **Big**    | `DeviceDescriptor`, `ErrorReport` |
| Windows → Phone    | **Little** | `Resolution`, `Bitrate`, `Zoom`, `AdaptiveBitrate` |

iOS implementations **must** mirror this quirk exactly. Helpers
[`ByteWriter`](../ios/VCamdroidiOS/Sources/VCamdroidiOS/Networking/ByteWriter.swift)
and
[`ByteReader`](../ios/VCamdroidiOS/Sources/VCamdroidiOS/Networking/ByteReader.swift)
expose explicit big- and little-endian methods to keep this honest.

---

## Control Channel (port 6969)

### 1. Initial Handshake

After TCP connect, the phone sends **one** descriptor message. Windows performs
a single `read_some(512)` to receive it. The descriptor must fit inside a
single segment, so total length must stay under ~512 bytes.

#### `DeviceDescriptor` (Phone → Windows, big-endian)

```
[uint16 nameLen]      [nameLen bytes UTF-8]              # human-readable name
[uint16 urlLen]       [urlLen bytes UTF-8]               # see "URL formats" below
[uint16 frontResCount]
  [uint16 width][uint16 height] ... frontResCount times
[uint16 backResCount]
  [uint16 width][uint16 height] ... backResCount times
[uint16 filterCount]
  [uint16 nameLen][nameLen bytes UTF-8][uint8 category]  # per filter
```

`category` values follow the C++ enum `Video::Filter::Category`:

| Value | Meaning      |
|-------|--------------|
| 0     | NONE         |
| 1     | CORRECTION   |
| 2     | EFFECT       |
| 3     | DISTORTION   |
| 4     | ARTISTIC     |

#### URL formats

The first 4 bytes of the URL string field are inspected by the Windows
`Serializer::DeserializeDeviceDescriptor` to determine `deviceType`:

| Prefix                  | Device type | Video transport |
|-------------------------|-------------|-----------------|
| `rtsp://`               | Android     | RTSP            |
| `vcmd://`               | iOS         | Raw TCP H.264 NAL |

For iOS, the URL must be of the form
`vcmd://<host>:<port>/v1?codec=h264&w=1920&h=1080&fps=30`.
The query string is optional; when present, it primes the Windows decoder for
the expected format before the first frame arrives.

For Android, the URL is unchanged: `rtsp://<host>:8554/live`. If the URL
contains the literal `127.0.0.1`, Windows forces `rtsp_transport=tcp` because
the stream is travelling through `adb forward` rather than a real network.

### 2. Activation (Windows → Phone)

When the user selects a device in the Windows UI, Windows transmits an
**ACTIVATION** packet that contains the full `StreamOptions` snapshot.

```
byte 0:  0x02                                            # PacketType::ACTIVATION
uint32  fps                          (big-endian)
uint32  width                        (big-endian)
uint32  height                       (big-endian)
uint32  backCameraActive  (bool)     (big-endian)
uint32  adaptiveBitrate   (bool)     (big-endian)
uint32  bitrate                      (big-endian)
uint32  minBitrate                   (big-endian)
uint32  maxBitrate                   (big-endian)
uint32  stabilizationEnabled (bool)  (big-endian)
uint32  flashEnabled         (bool)  (big-endian)
uint32  h265Enabled          (bool)  (big-endian)
uint16  filterValueCount             (big-endian)
  uint16 nameLen
  bytes  filterName (UTF-8)
  uint32 sliderValue          (big-endian)
... repeat filterValueCount times
uint16  effectFilterNameLen          (big-endian)
bytes   effectFilterName (UTF-8)
```

> Activation is the **only** Windows→Phone packet that uses big-endian.
> Everything below uses little-endian (matching the Android implementation in
> `windows/src/rtsp/manager.cpp`).

### 3. Commands (Windows → Phone, little-endian where noted)

Every command begins with a 1-byte opcode.

#### Core opcodes (v1, supported by both Android and iOS)

| Op   | Name                | Payload                                                                     |
|------|---------------------|-----------------------------------------------------------------------------|
| 0x00 | FRAME               | unused                                                                      |
| 0x01 | RESOLUTION          | `uint16 LE width`, `uint16 LE height`                                       |
| 0x02 | ACTIVATION          | (see Activation above)                                                      |
| 0x03 | CAMERA              | (no payload — swap front/back)                                              |
| 0x04 | QUALITY             | unused (reserved)                                                           |
| 0x05 | CORRECTION_FILTER   | `uint8 nameLen`, `bytes name (UTF-8)`, `uint8 value (0..100)`               |
| 0x06 | EFFECT_FILTER       | `uint8 nameLen`, `bytes name (UTF-8)`                                       |
| 0x07 | ROTATION            | `int8 degrees`                                                              |
| 0x08 | BITRATE             | `uint16 LE kbps`                                                            |
| 0x09 | ADAPTIVE_BITRATE    | `uint16 LE minKbps`, `uint16 LE maxKbps`                                    |
| 0x0A | STABILIZATION       | `uint8 enabled (0/1)`                                                       |
| 0x0B | FLASH               | `uint8 enabled (0/1)`                                                       |
| 0x0C | FOCUS               | `uint8 mode (0=auto, 1=manual)`                                             |
| 0x0D | CODEC               | `uint8 h265 (0/1)`                                                          |
| 0x0E | FPS                 | `uint8 fps`                                                                 |
| 0x0F | ZOOM                | `float32 LE factor` (Android: digital zoom multiplier)                      |
| 0x10 | FLIP                | `uint8 axis (1=horizontal, 0=vertical)`                                     |

#### iOS premium-control opcodes (v2)

| Op   | Name                       | Payload                                                              |
|------|----------------------------|----------------------------------------------------------------------|
| 0x20 | LENS_ZOOM                  | `float32 LE zoomFactor` (1.0x–telephoto max, virtual-device aware)   |
| 0x21 | EXPOSURE                   | `float32 LE durationSeconds`, `float32 LE iso`                       |
| 0x22 | WHITE_BALANCE              | `float32 LE temperatureK`, `float32 LE tint`                         |
| 0x23 | STUDIO_MODE                | `uint8 enabled (0/1)`                                                |
| 0x24 | EXPOSURE_COMPENSATION      | `float32 LE evBias`                                                  |
| 0x25 | STABILIZATION_MODE         | `uint8 mode (0=off, 1=standard, 2=cinematic, 3=cinematicExtended)`   |
| 0x26 | FOCUS_LOCK                 | `float32 LE lensPosition (0.0–1.0)` or `0xFFFFFFFF` to release       |
| 0x27 | TAP_TO_FOCUS               | `float32 LE x (0–1)`, `float32 LE y (0–1)`                           |
| 0x28 | MIC_ENABLED                | `uint8 enabled (0/1)`                                                |
| 0x29 | SNAPSHOT_REQUEST           | (no payload)                                                         |
| 0x2A | RESET_CAMERA_TO_AUTO       | (no payload — releases all manual locks)                             |

Android implementations should **ignore** unknown opcodes rather than crash;
iOS implementations should treat opcodes ≥ 0x20 they don't yet understand the
same way (forward compatibility).

### 4. Snapshot Response (Phone → Windows, big-endian)

Sent by the phone after handling a `SNAPSHOT_REQUEST` opcode. The payload is a
JPEG-encoded frame, which the Windows side may write to disk or hand off to
the host application.

```
uint8   opcode = 0x40
uint32  jpegLength                         (big-endian)
bytes   jpegBytes
```

The phone may take up to ~200 ms to fulfill a snapshot request (it forces a
keyframe and waits for the next pixel buffer). Snapshots are throttled
client-side to no more than one outstanding request at a time.

### 5. Error Reports (Phone → Windows, big-endian)

```
uint8   severity (0=warning, 1=error)
uint16  errorLen
bytes   error (UTF-8)
uint16  descriptionLen
bytes   description (UTF-8)
```

Sent in response to non-recoverable conditions such as resolution unsupported,
encoder init failure, etc.

---

## Video Channel (port 8554)

### Android: RTSP

Unchanged from v1. The Android app exposes an RTSP server (RootEncoder /
`RtspServerCamera2`) that serves H.264 or H.265 over RTP/RTSP.

### iOS: Raw TCP NAL framing

The iOS app exposes a single TCP listener on `0.0.0.0:8554`. When the Windows
client connects, the connection lifecycle is:

#### 1. Header (iOS → Windows, exactly once after accept)

```
uint32 magic     = 0x56434D44                            # ASCII "VCMD"
uint8  version   = 0x01
uint8  codec                                             # 0x01=H.264, 0x02=H.265
uint16 width                              (big-endian)
uint16 height                             (big-endian)
uint8  fps
```

#### 2. NAL stream

Each subsequent message is a single H.264 or H.265 NAL unit:

```
uint32 nalLength                          (big-endian)
bytes  rawNalUnit (no Annex-B start code, no AVCC length prefix duplication)
```

Codec parameter NAL units (SPS / PPS for H.264; VPS / SPS / PPS for H.265) are
sent in-band ahead of the first IDR frame, and re-sent on every keyframe to
allow mid-stream tune-in. They are normal NAL units; nothing special is
required from the Windows decoder beyond the standard ffmpeg path.

The Windows side converts each received NAL unit back into Annex-B form
(`00 00 00 01 <nal>`) before feeding it to `avcodec_send_packet`. This is the
simplest interoperable form for ffmpeg.

#### 3. Backpressure & keyframes

- The iOS encoder is configured for real-time, low-latency rate control with
  a target keyframe interval of 30 frames (≈ 1 second at 30 fps).
- If a Windows-side decode error indicates lost SPS/PPS context, the iOS app
  must respond to the next ACTIVATION (or new TCP connect) by forcing an
  immediate keyframe via `VTCompressionSessionCompleteFrames` + a frame
  property request.

#### 4. Disconnect

A TCP FIN from Windows signals "stop streaming". The iOS encoder must drain
in-flight frames, tear down `VTCompressionSession`, and return to idle so the
next ACTIVATION starts a clean session.

---

## Phase 3: Discovery via Bonjour (`_vcamdroid._tcp.`)

The iOS app advertises itself on the local network using `NWListener` /
`NetService` with the service type `_vcamdroid._tcp.` on the control port
(6969). TXT records expose:

| Key       | Value                                       |
|-----------|---------------------------------------------|
| `dev`     | `ios` (or `android` if/when extended)       |
| `name`    | Display name (e.g. "iPhone 16 Pro")          |
| `version` | Protocol version (`2`)                       |
| `ctl`     | Control port (`6969`)                       |
| `vid`     | Video port (`8554`)                         |

The Windows client uses `mdns_query` to enumerate
`_vcamdroid._tcp.local.` and populate the source dropdown automatically,
removing the QR-code step for Wi-Fi pairing.

---

## Versioning Rules

- **Bumping the protocol version** is required whenever a wire-incompatible
  change is made to descriptor parsing, activation, or video framing.
- New opcodes are **always additive** and may be introduced without bumping
  the version.
- Phone implementations must treat unknown opcodes as no-ops and continue.
- Windows implementations must accept descriptors that omit the v2 magic and
  treat them as Android v1.
