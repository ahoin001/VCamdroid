import Foundation

/// Decodes the body of an ACTIVATION packet (everything after the 0x02 opcode)
/// into a `StreamConfiguration`. Matches `Serializer::SerializeStreamOptions`
/// in `windows/src/net/serializer.cpp`.
public enum ActivationDecoder {
    public enum Error: Swift.Error, Equatable {
        case truncated
        case malformedString
    }

    /// Parses the ACTIVATION body. The caller must have already consumed the
    /// 1-byte opcode.
    public static func decode(body: Data) throws -> StreamConfiguration {
        var reader = ByteReader(body)
        do {
            let fps              = Int(try reader.readUInt32BE())
            let width            = Int(try reader.readUInt32BE())
            let height           = Int(try reader.readUInt32BE())
            let useBackCamera    = try reader.readBool32BE()
            let adaptive         = try reader.readBool32BE()
            let bitrate          = Int(try reader.readUInt32BE())
            let minBitrate       = Int(try reader.readUInt32BE())
            let maxBitrate       = Int(try reader.readUInt32BE())
            let stabilization    = try reader.readBool32BE()
            let flash            = try reader.readBool32BE()
            let h265             = try reader.readBool32BE()

            var filters: [String: Int] = [:]
            let filterCount = Int(try reader.readUInt16BE())
            for _ in 0..<filterCount {
                let name = try reader.readLengthPrefixedStringBE()
                let value = Int(try reader.readUInt32BE())
                filters[name] = value
            }

            let activeEffect = try reader.readLengthPrefixedStringBE()
            let normalizedEffect: String? = activeEffect.isEmpty ? nil : activeEffect

            return StreamConfiguration(
                fps: fps,
                width: width,
                height: height,
                useBackCamera: useBackCamera,
                adaptiveBitrate: adaptive,
                bitrateKbps: bitrate,
                minBitrateKbps: minBitrate,
                maxBitrateKbps: maxBitrate,
                stabilizationEnabled: stabilization,
                flashEnabled: flash,
                h265Enabled: h265,
                filterValues: filters,
                activeEffectFilter: normalizedEffect
            )
        } catch ByteReader.Error.unexpectedEndOfStream {
            throw Error.truncated
        } catch ByteReader.Error.invalidUTF8 {
            throw Error.malformedString
        }
    }
}
