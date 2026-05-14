import Foundation
import CoreMedia
import VideoToolbox

/// Extracts H.264 / H.265 NAL units (and their parameter sets) from a
/// `CMSampleBuffer` produced by `VTCompressionSession`. VideoToolbox emits
/// frames in **AVCC** (length-prefixed) form, so this helper:
///
/// 1. Reads the AVCC `lengthSizeMinusOne` from the format description to
///    determine whether NALs are length-prefixed with 4, 2, or 1 byte values.
/// 2. Splits the CMBlockBuffer into individual NAL units.
/// 3. On keyframes, additionally returns the parameter set NALs (SPS/PPS for
///    H.264; VPS/SPS/PPS for H.265) so the decoder on the Windows side can
///    initialize / tune-in mid-stream.
///
/// Callers should send the returned NALs in order (`parameterSets` first,
/// then `pictureNALs`).
public enum NALUnitExtractor {

    public struct Output {
        public let parameterSets: [Data]
        public let pictureNALs: [Data]
        public let isKeyframe: Bool
    }

    public enum Codec {
        case h264
        case h265
    }

    public static func extract(from sampleBuffer: CMSampleBuffer, codec: Codec) -> Output? {
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]]
        let notSync = attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
        let isKeyframe = !notSync

        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }

        var lengthSize = 4
        var parameterSets: [Data] = []

        if isKeyframe {
            parameterSets = extractParameterSets(from: formatDesc, codec: codec, lengthSize: &lengthSize)
        } else {
            // Even on non-keyframes we still need the length-size from the
            // format description to walk the AVCC NAL boundaries.
            _ = extractParameterSets(from: formatDesc, codec: codec, lengthSize: &lengthSize, collect: false)
        }

        let pictureNALs = splitAVCC(blockBuffer: blockBuffer, lengthSize: lengthSize)
        return Output(parameterSets: parameterSets, pictureNALs: pictureNALs, isKeyframe: isKeyframe)
    }

    // MARK: - Internal helpers

    private static func extractParameterSets(
        from formatDesc: CMFormatDescription,
        codec: Codec,
        lengthSize: inout Int,
        collect: Bool = true
    ) -> [Data] {
        var sets: [Data] = []

        // First call: discover the count.
        var setCount = 0
        var nalUnitHeaderLength: Int32 = 4

        let probeStatus: OSStatus
        switch codec {
        case .h264:
            probeStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                formatDesc, parameterSetIndex: 0, parameterSetPointerOut: nil,
                parameterSetSizeOut: nil, parameterSetCountOut: &setCount,
                nalUnitHeaderLengthOut: &nalUnitHeaderLength
            )
        case .h265:
            probeStatus = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                formatDesc, parameterSetIndex: 0, parameterSetPointerOut: nil,
                parameterSetSizeOut: nil, parameterSetCountOut: &setCount,
                nalUnitHeaderLengthOut: &nalUnitHeaderLength
            )
        }
        guard probeStatus == noErr else { return [] }
        lengthSize = Int(nalUnitHeaderLength)

        guard collect else { return [] }

        for i in 0..<setCount {
            var pointer: UnsafePointer<UInt8>?
            var size: Int = 0
            let status: OSStatus
            switch codec {
            case .h264:
                status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                    formatDesc, parameterSetIndex: i,
                    parameterSetPointerOut: &pointer, parameterSetSizeOut: &size,
                    parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil
                )
            case .h265:
                status = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                    formatDesc, parameterSetIndex: i,
                    parameterSetPointerOut: &pointer, parameterSetSizeOut: &size,
                    parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil
                )
            }
            if status == noErr, let pointer {
                sets.append(Data(bytes: pointer, count: size))
            }
        }
        return sets
    }

    private static func splitAVCC(blockBuffer: CMBlockBuffer, lengthSize: Int) -> [Data] {
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )
        guard status == kCMBlockBufferNoErr, let raw = dataPointer else { return [] }

        let base = UnsafeRawPointer(raw).assumingMemoryBound(to: UInt8.self)
        var out: [Data] = []
        var offset = 0

        while offset + lengthSize <= totalLength {
            var nalSize = 0
            // AVCC length field is big-endian, variable width (1, 2, or 4).
            for byte in 0..<lengthSize {
                nalSize = (nalSize << 8) | Int(base[offset + byte])
            }
            offset += lengthSize
            guard offset + nalSize <= totalLength else { break }
            out.append(Data(bytes: base + offset, count: nalSize))
            offset += nalSize
        }
        return out
    }
}
