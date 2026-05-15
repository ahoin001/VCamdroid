import Foundation

/// Strongly-typed representation of every Windows → phone command. The
/// underlying byte layout is captured in `docs/PROTOCOL.md`.
public enum ControlCommand: Equatable, Sendable {
    // v1
    case activation(StreamConfiguration)
    case setResolution(width: Int, height: Int)
    case swapCamera
    case correctionFilter(name: String, value: Int)
    case effectFilter(name: String)
    case rotate(degrees: Int)
    case setBitrate(kbps: Int)
    case setAdaptiveBitrate(minKbps: Int, maxKbps: Int)
    case setStabilization(Bool)
    case setFlash(Bool)
    case setFocusMode(FocusMode)
    case setCodec(useH265: Bool)
    case setFps(Int)
    case setZoom(Float)
    case flip(FlipAxis)

    // v2 — iOS premium controls
    case setLensZoom(Float)
    case setExposure(durationSeconds: Float, iso: Float)
    case setWhiteBalance(temperatureK: Float, tint: Float)
    case setStudioMode(Bool)
    case setExposureCompensation(Float)
    case setStabilizationMode(StabilizationMode)
    case setFocusLock(lensPosition: Float?)
    case tapToFocus(x: Float, y: Float)
    case setMicrophone(enabled: Bool)
    case snapshotRequest
    case resetCameraToAuto
    case setPortraitMode(enabled: Bool, strength: Int)

    /// Forward-compatibility fallback for opcodes a build does not yet
    /// understand. We retain the raw bytes so they can be logged for
    /// debugging without crashing.
    case unknown(opcode: UInt8, payload: Data)
}
