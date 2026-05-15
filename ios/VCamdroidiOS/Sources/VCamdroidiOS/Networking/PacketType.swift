import Foundation

/// Mirrors `windows/src/rtsp/manager.h :: RTSP::Manager::Command` and the
/// Android `PacketType.kt` companion object. Stays byte-compatible with both.
public enum PacketType: UInt8 {
    // v1 — shared with Android
    case frame             = 0x00
    case resolution        = 0x01
    case activation        = 0x02
    case camera            = 0x03
    case quality           = 0x04
    case correctionFilter  = 0x05
    case effectFilter      = 0x06
    case rotation          = 0x07
    case bitrate           = 0x08
    case adaptiveBitrate   = 0x09
    case stabilization     = 0x0A
    case flash             = 0x0B
    case focus             = 0x0C
    case codec             = 0x0D
    case fps               = 0x0E
    case zoom              = 0x0F
    case flip              = 0x10

    // v2 — iOS premium controls
    case lensZoom              = 0x20
    case exposure              = 0x21
    case whiteBalance          = 0x22
    case studioMode            = 0x23
    case exposureCompensation  = 0x24
    case stabilizationMode     = 0x25
    case focusLock             = 0x26
    case tapToFocus            = 0x27
    case micEnabled            = 0x28
    case snapshotRequest       = 0x29
    case resetCameraToAuto     = 0x2A
    case portraitMode          = 0x2B
}

public enum FlipAxis: UInt8 {
    case vertical = 0
    case horizontal = 1
}

public enum FocusMode: UInt8 {
    case auto = 0
    case manual = 1
}

public enum StabilizationMode: UInt8 {
    case off = 0
    case standard = 1
    case cinematic = 2
    case cinematicExtended = 3
}
