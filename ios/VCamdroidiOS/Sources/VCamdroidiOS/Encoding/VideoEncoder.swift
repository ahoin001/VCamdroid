import Foundation
import CoreMedia
import CoreVideo

/// Protocol abstraction so the orchestrator can be tested with a fake encoder
/// and the underlying VideoToolbox implementation can be swapped later
/// (for example, for HEVC, software fallback, or a hardware-side filter).
public protocol VideoEncoder: AnyObject {
    var delegate: VideoEncoderDelegate? { get set }

    func configure(_ config: VideoEncoderConfig) throws
    func encode(pixelBuffer: CVPixelBuffer, presentationTime: CMTime, forceKeyframe: Bool)
    func requestKeyframe()
    func updateBitrate(_ kbps: Int)
    func teardown()
}

public protocol VideoEncoderDelegate: AnyObject {
    /// Called for every emitted NAL unit. Already framed for the VCamdroid
    /// wire protocol (no AVCC length prefix, no Annex-B start code).
    func videoEncoder(_ encoder: VideoEncoder, didEmit nal: Data, isParameterSet: Bool, isKeyframe: Bool, presentationTime: CMTime)
    func videoEncoder(_ encoder: VideoEncoder, didFailWith error: Error)
}

public struct VideoEncoderConfig: Equatable {
    public enum Codec { case h264, h265 }

    public let codec: Codec
    public let width: Int
    public let height: Int
    public let fps: Int
    public let bitrateBps: Int
    public let keyframeIntervalFrames: Int

    public init(codec: Codec, width: Int, height: Int, fps: Int, bitrateBps: Int, keyframeIntervalFrames: Int = 30) {
        self.codec = codec
        self.width = width
        self.height = height
        self.fps = fps
        self.bitrateBps = bitrateBps
        self.keyframeIntervalFrames = keyframeIntervalFrames
    }
}
