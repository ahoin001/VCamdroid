import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

/// VideoToolbox-backed implementation of `VideoEncoder`. Built for low
/// latency: real-time rate control, no B-frames, IDR-friendly keyframe
/// cadence, and the source `CVPixelBuffer` flows through without leaving
/// IOSurface-backed GPU memory.
///
/// Encoder lifetime is driven by `configure(_:)`. On every reconfigure
/// (resolution / fps / codec / bitrate change) we tear the session down and
/// build a new one — this matches what AVFoundation needs for reliable
/// hardware encoder behavior on iPhone.
public final class VTH264Encoder: VideoEncoder {

    public weak var delegate: VideoEncoderDelegate?

    private var session: VTCompressionSession?
    private var config: VideoEncoderConfig?
    private let lock = NSLock()

    public init() {}

    public func configure(_ config: VideoEncoderConfig) throws {
        teardown()

        var session: VTCompressionSession?
        let codecType: CMVideoCodecType = (config.codec == .h265) ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(config.width),
            height: Int32(config.height),
            codecType: codecType,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: VTH264Encoder.outputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &session
        )
        guard status == noErr, let session else {
            throw NSError(domain: "VCamdroid", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "VTCompressionSessionCreate failed"])
        }

        // Latency-tuned properties. Setters that fail are logged but not
        // fatal — older devices may not support every property.
        let frameInterval = NSNumber(value: config.keyframeIntervalFrames)
        let frameIntervalDuration = NSNumber(value: Double(config.keyframeIntervalFrames) / Double(config.fps))

        let props: [(CFString, CFTypeRef)] = [
            (kVTCompressionPropertyKey_RealTime, kCFBooleanTrue),
            (kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse),
            (kVTCompressionPropertyKey_AllowTemporalCompression, kCFBooleanTrue),
            (kVTCompressionPropertyKey_ExpectedFrameRate, NSNumber(value: config.fps)),
            (kVTCompressionPropertyKey_MaxKeyFrameInterval, frameInterval),
            (kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, frameIntervalDuration),
            (kVTCompressionPropertyKey_AverageBitRate, NSNumber(value: config.bitrateBps)),
            // Cap burst bitrate so a single noisy frame doesn't blow our budget.
            (kVTCompressionPropertyKey_DataRateLimits, [NSNumber(value: config.bitrateBps / 8 * 2), NSNumber(value: 1)] as CFArray),
            (kVTCompressionPropertyKey_H264EntropyMode, kVTH264EntropyMode_CABAC),
            (kVTCompressionPropertyKey_ProfileLevel, (config.codec == .h265) ? kVTProfileLevel_HEVC_Main_AutoLevel : kVTProfileLevel_H264_High_AutoLevel),
        ]
        for (key, value) in props {
            let s = VTSessionSetProperty(session, key: key, value: value)
            if s != noErr {
                Log.warning("encoder", "Unable to set \(key) (status \(s))")
            }
        }

        VTCompressionSessionPrepareToEncodeFrames(session)
        self.session = session
        self.config = config
        Log.info("encoder", "Configured \(config.codec) \(config.width)x\(config.height)@\(config.fps) \(config.bitrateBps/1000) kbps")
    }

    public func encode(pixelBuffer: CVPixelBuffer, presentationTime: CMTime, forceKeyframe: Bool) {
        guard let session = session else { return }
        var frameProperties: CFDictionary?
        if forceKeyframe {
            frameProperties = [kVTEncodeFrameOptionKey_ForceKeyFrame: kCFBooleanTrue] as CFDictionary
        }
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTime,
            duration: .invalid,
            frameProperties: frameProperties,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
        if status != noErr {
            Log.error("encoder", "EncodeFrame failed with status \(status)")
        }
    }

    public func requestKeyframe() {
        guard let session = session else { return }
        VTSessionSetProperty(session, key: kVTEncodeFrameOptionKey_ForceKeyFrame, value: kCFBooleanTrue)
    }

    public func updateBitrate(_ kbps: Int) {
        guard let session = session else { return }
        let bps = NSNumber(value: kbps * 1_000)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bps)
        // Burst limit follows the bitrate so the rate controller stays stable.
        let limits: CFArray = [NSNumber(value: kbps * 1_000 / 8 * 2), NSNumber(value: 1)] as CFArray
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: limits)
    }

    public func teardown() {
        lock.lock()
        defer { lock.unlock() }
        if let session {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session)
            self.session = nil
        }
        config = nil
    }

    // MARK: - VT output callback

    private static let outputCallback: VTCompressionOutputCallback = { (
        outputCallbackRefCon,
        _ /* sourceFrameRefCon */,
        status,
        _ /* infoFlags */,
        sampleBuffer
    ) in
        guard status == noErr, let sampleBuffer, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        guard let refcon = outputCallbackRefCon else { return }
        let encoder = Unmanaged<VTH264Encoder>.fromOpaque(refcon).takeUnretainedValue()
        encoder.handleEncoded(sampleBuffer)
    }

    private func handleEncoded(_ sampleBuffer: CMSampleBuffer) {
        guard let config else { return }
        let codec: NALUnitExtractor.Codec = (config.codec == .h265) ? .h265 : .h264
        guard let output = NALUnitExtractor.extract(from: sampleBuffer, codec: codec) else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        for set in output.parameterSets {
            delegate?.videoEncoder(self, didEmit: set, isParameterSet: true, isKeyframe: output.isKeyframe, presentationTime: pts)
        }
        for nal in output.pictureNALs {
            delegate?.videoEncoder(self, didEmit: nal, isParameterSet: false, isKeyframe: output.isKeyframe, presentationTime: pts)
        }
    }
}
