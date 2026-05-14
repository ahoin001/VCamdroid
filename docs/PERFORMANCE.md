# VCamdroid Performance & Hardening Notes

This document captures the performance characteristics, profiling
methodology, and hardening passes we've applied to keep VCamdroid running
within the "PC wallpaper-engine-class" resource budget while delivering a
premium phone-camera experience.

## Latency Budget (target)

End-to-end glass-to-pixel goal: **≤ 90 ms** on USB tunneling and **≤ 140
ms** on Wi-Fi with a healthy LAN. Component budgets:

| Stage                                | Budget (ms) | Notes |
|--------------------------------------|-------------|-------|
| iOS capture queue → encoder          | 5           | `AVCaptureVideoDataOutput` callback only forwards the `CVPixelBuffer` reference (IOSurface-backed; zero copy). |
| `VTCompressionSession` encode        | 18–22       | Real-time rate control, B-frames disabled, CABAC enabled. |
| TCP send (USB)                       | 5–10        | `tcp_nodelay = true`, single in-flight NAL per `NWConnection.send`. |
| TCP send (Wi-Fi healthy)             | 10–25       | Same plus PHY/MAC variance. |
| Windows TCP receive + NAL deframe    | 2           | Pre-allocated 256 KB scratch buffer. |
| FFmpeg decode (`thread_count=4`)     | 8–12        | `AV_CODEC_FLAG_LOW_DELAY`, slice threading only (no frame threading). |
| Render to preview / Softcam          | 5–10        | DirectShowScaler copies once per frame; OBS plugin path skips this. |

If sustained latency exceeds the budget, the ABR controller drops bitrate by
20% with a 2 s cooldown; if the encoder consistently undershoots the target
FPS, the controller waits, then bumps back up by 10% once `fps ≥ 98% of
target` for the cooldown window.

## Resource budget (target)

| Resource | Target |
|----------|--------|
| Windows CPU (idle, no preview)        | < 1%   |
| Windows CPU (streaming 1080p30)       | 4–8%   |
| Windows GPU (streaming 1080p30)       | 2–5%   |
| Windows RSS                            | ≤ 150 MB |
| iPhone CPU (streaming 1080p30 h264)    | 6–12%  |
| iPhone battery drain (cold device)     | < 18%/hr at 1080p30 |
| iPhone surface temperature             | < 38 °C after 30 min |

The iOS app keeps the screen at minimum brightness in Studio Mode and
enables `UIApplication.shared.isIdleTimerDisabled = true` only while
streaming. The Windows client uses a single condition-variable wakeup per
frame instead of polling, and the decoder thread is the only CPU-bound
worker.

## Backpressure & Hot-Path Safety

iOS:
- `VideoStreamServer` tracks outstanding bytes in `pendingSendBytes`. Above
  the 4 MB high-water mark, *non-parameter, non-keyframe* NAL units are
  dropped to keep the kernel send buffer from ballooning under stalled
  receivers. Keyframes and SPS/PPS/VPS are always sent so the Windows
  decoder can recover.
- `StreamController._configurationSnapshot` is read under a lock by the
  encoder/network threads; the `@Published` `configuration` is only mutated
  from the `MainActor`. No `DispatchSemaphore` waits on `MainActor`.
- The capture session, encoder, and network listeners each have their own
  serial dispatch queue and never call back into one another synchronously.

Windows:
- `RTSP::Manager` owns its `IFrameReceiver`. Switching devices tears the
  receiver down before constructing a new one — the decode thread never
  races with main thread reconfigure.
- `RawTCPReceiver::WorkerFunc` reuses a 256 KB scratch vector and reads
  Annex-B straight into it; no per-frame allocations except FFmpeg's
  internal frame pool.
- `Streaming::IFrameReceiver` is the only place where the FFmpeg
  `AVCodecContext` is touched. The render thread only reads decoded
  `AVFrame` references handed off via the existing `OnFrameReceived`
  callback.

## Memory & Allocation Hot Paths

- **iOS encoder**: `VTCompressionSession` returns IOSurface-backed
  `CVPixelBuffer`s; we never deep-copy frames.
- **iOS NAL extraction**: `NALUnitExtractor` walks the AVCC `CMBlockBuffer`
  in place, allocating one `Data` per emitted NAL. Roughly 4 NALs per frame
  at 30 fps = 120 allocations/sec, easily handled by the Swift allocator.
- **Windows NAL framing**: pre-sized scratch buffer in `RawTCPReceiver`;
  re-used across frames.

## Profiling Methodology

When investigating regressions:

1. **iOS encode latency** — use Instruments "Time Profiler" + "System
   Trace". The `vcamdroid.video.io` and `VTCompressionSession` queues should
   each stay below 35% utilization.
2. **iOS thermal state** — observe `ProcessInfo.processInfo.thermalState`.
   If it transitions to `.serious` or `.critical` we drop bitrate by 20%
   and emit an `ErrorReport` to the Windows client.
3. **Windows decode latency** — feed wall-clock timestamps from the iOS
   `presentationTime` into the existing `Stats` callback so the UI shows
   end-to-end latency, not just decode time. The receiver's per-second
   `Stats` is the cheapest hook.
4. **OBS path** — once the dedicated plugin lands, use `obs --profile
   --verbose-log` and compare against the DirectShow path to validate the
   ≥ 30 ms latency improvement we expect from skipping Softcam's ring
   buffer.

## Hardening Checklist

- [x] iOS lock-protected config snapshot (no MainActor blocking)
- [x] iOS dropped-frame backpressure on TCP send
- [x] Windows pre-allocated NAL deframing buffer
- [x] Windows receiver lifetime owned by `RTSP::Manager`
- [x] ABR cooldown to prevent ping-ponging
- [x] Snapshot/audio paths cleared in `disconnect()` (no leaked state)
- [x] Multi-iOS device support via `stateRegistry` keyed by device name
- [x] iOS premium control state persisted per device

## Known Future Work

- Replace the JPEG snapshot path with HEIC for ~30% smaller payloads (and
  to match iPhone-native exports).
- Add OBS plugin once libobs is available locally (see `obs-plugin/README.md`).
- Wire `libusbmuxd` USB tunneling for iOS (the current `UsbmuxBridge` is a
  stub).
- Surface per-frame latency in the UI overlay for both iOS and Windows so
  users can self-diagnose Wi-Fi quality.
