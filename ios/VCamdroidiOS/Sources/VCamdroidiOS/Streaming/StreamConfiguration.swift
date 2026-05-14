import Foundation

/// Immutable snapshot of the stream configuration the Windows client wants the
/// phone to honor. Built by decoding the ACTIVATION packet.
///
/// Designed to be value-typed and `Sendable` so it can be safely fanned out
/// to capture / encode / network actors without locking.
public struct StreamConfiguration: Equatable, Sendable {
    public var fps: Int
    public var width: Int
    public var height: Int
    public var useBackCamera: Bool

    public var adaptiveBitrate: Bool
    public var bitrateKbps: Int
    public var minBitrateKbps: Int
    public var maxBitrateKbps: Int

    public var stabilizationEnabled: Bool
    public var flashEnabled: Bool
    public var h265Enabled: Bool

    public var filterValues: [String: Int]
    public var activeEffectFilter: String?

    public init(
        fps: Int = 30,
        width: Int = 1280,
        height: Int = 720,
        useBackCamera: Bool = true,
        adaptiveBitrate: Bool = false,
        bitrateKbps: Int = 4_000,
        minBitrateKbps: Int = 2_000,
        maxBitrateKbps: Int = 12_000,
        stabilizationEnabled: Bool = false,
        flashEnabled: Bool = false,
        h265Enabled: Bool = false,
        filterValues: [String: Int] = [:],
        activeEffectFilter: String? = nil
    ) {
        self.fps = fps
        self.width = width
        self.height = height
        self.useBackCamera = useBackCamera
        self.adaptiveBitrate = adaptiveBitrate
        self.bitrateKbps = bitrateKbps
        self.minBitrateKbps = minBitrateKbps
        self.maxBitrateKbps = maxBitrateKbps
        self.stabilizationEnabled = stabilizationEnabled
        self.flashEnabled = flashEnabled
        self.h265Enabled = h265Enabled
        self.filterValues = filterValues
        self.activeEffectFilter = activeEffectFilter
    }
}
