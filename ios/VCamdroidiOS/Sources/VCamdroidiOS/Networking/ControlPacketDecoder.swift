import Foundation

/// Parses a raw control-channel byte buffer into a sequence of typed
/// `ControlCommand`s. The Android implementation uses a similar
/// "first-byte-is-opcode" pattern in `StreamActivity.kt`.
///
/// The decoder is intentionally a pure function so it can be exercised by
/// `XCTest` without touching the network.
public enum ControlPacketDecoder {
    /// Decodes exactly one command starting at the head of `data`.
    /// Returns the command plus the number of bytes consumed, so a caller
    /// processing a stream can slide the buffer forward.
    public static func decodeOne(_ data: Data) throws -> (ControlCommand, consumed: Int)? {
        guard !data.isEmpty else { return nil }
        let opcode = data[data.startIndex]
        let body = data.dropFirst()

        switch PacketType(rawValue: opcode) {
        case .activation:
            let cfg = try ActivationDecoder.decode(body: body)
            return (.activation(cfg), data.count)

        case .resolution:
            var reader = ByteReader(body)
            let w = Int(try reader.readUInt16LE())
            let h = Int(try reader.readUInt16LE())
            return (.setResolution(width: w, height: h), 1 + reader.offset)

        case .camera:
            return (.swapCamera, 1)

        case .correctionFilter:
            var reader = ByteReader(body)
            let name = try reader.readShortPrefixedString()
            let value = Int(try reader.readUInt8())
            return (.correctionFilter(name: name, value: value), 1 + reader.offset)

        case .effectFilter:
            var reader = ByteReader(body)
            let name = try reader.readShortPrefixedString()
            return (.effectFilter(name: name), 1 + reader.offset)

        case .rotation:
            var reader = ByteReader(body)
            let degrees = Int(Int8(bitPattern: try reader.readUInt8()))
            return (.rotate(degrees: degrees), 1 + reader.offset)

        case .bitrate:
            var reader = ByteReader(body)
            let kbps = Int(try reader.readUInt16LE())
            return (.setBitrate(kbps: kbps), 1 + reader.offset)

        case .adaptiveBitrate:
            var reader = ByteReader(body)
            let lo = Int(try reader.readUInt16LE())
            let hi = Int(try reader.readUInt16LE())
            return (.setAdaptiveBitrate(minKbps: lo, maxKbps: hi), 1 + reader.offset)

        case .stabilization:
            var reader = ByteReader(body)
            let enabled = try reader.readUInt8() != 0
            return (.setStabilization(enabled), 1 + reader.offset)

        case .flash:
            var reader = ByteReader(body)
            let enabled = try reader.readUInt8() != 0
            return (.setFlash(enabled), 1 + reader.offset)

        case .focus:
            var reader = ByteReader(body)
            let mode = FocusMode(rawValue: try reader.readUInt8()) ?? .auto
            return (.setFocusMode(mode), 1 + reader.offset)

        case .codec:
            var reader = ByteReader(body)
            let h265 = try reader.readUInt8() != 0
            return (.setCodec(useH265: h265), 1 + reader.offset)

        case .fps:
            var reader = ByteReader(body)
            let fps = Int(try reader.readUInt8())
            return (.setFps(fps), 1 + reader.offset)

        case .zoom:
            var reader = ByteReader(body)
            let factor = try reader.readFloat32LE()
            return (.setZoom(factor), 1 + reader.offset)

        case .flip:
            var reader = ByteReader(body)
            let raw = try reader.readUInt8()
            let axis: FlipAxis = (raw == 1) ? .horizontal : .vertical
            return (.flip(axis), 1 + reader.offset)

        case .lensZoom:
            var reader = ByteReader(body)
            let z = try reader.readFloat32LE()
            return (.setLensZoom(z), 1 + reader.offset)

        case .exposure:
            var reader = ByteReader(body)
            let dur = try reader.readFloat32LE()
            let iso = try reader.readFloat32LE()
            return (.setExposure(durationSeconds: dur, iso: iso), 1 + reader.offset)

        case .whiteBalance:
            var reader = ByteReader(body)
            let temp = try reader.readFloat32LE()
            let tint = try reader.readFloat32LE()
            return (.setWhiteBalance(temperatureK: temp, tint: tint), 1 + reader.offset)

        case .studioMode:
            var reader = ByteReader(body)
            let enabled = try reader.readUInt8() != 0
            return (.setStudioMode(enabled), 1 + reader.offset)

        case .exposureCompensation:
            var reader = ByteReader(body)
            let bias = try reader.readFloat32LE()
            return (.setExposureCompensation(bias), 1 + reader.offset)

        case .stabilizationMode:
            var reader = ByteReader(body)
            let mode = StabilizationMode(rawValue: try reader.readUInt8()) ?? .off
            return (.setStabilizationMode(mode), 1 + reader.offset)

        case .focusLock:
            var reader = ByteReader(body)
            let raw = try reader.readUInt32LE()
            // 0xFFFFFFFF is the sentinel for "release lock and return to auto".
            let pos: Float? = (raw == 0xFFFFFFFF) ? nil : Float(bitPattern: raw)
            return (.setFocusLock(lensPosition: pos), 1 + reader.offset)

        case .tapToFocus:
            var reader = ByteReader(body)
            let x = try reader.readFloat32LE()
            let y = try reader.readFloat32LE()
            return (.tapToFocus(x: x, y: y), 1 + reader.offset)

        case .micEnabled:
            var reader = ByteReader(body)
            let enabled = try reader.readUInt8() != 0
            return (.setMicrophone(enabled: enabled), 1 + reader.offset)

        case .snapshotRequest:
            return (.snapshotRequest, 1)

        case .resetCameraToAuto:
            return (.resetCameraToAuto, 1)

        case .frame, .quality, .none:
            // 0x00 / 0x04 / unknown: surface as unknown so callers can log.
            return (.unknown(opcode: opcode, payload: Data(body)), data.count)
        }
    }

    /// Drains an entire buffer into one or more commands. Stops when there's
    /// not enough remaining bytes to parse another command.
    public static func decodeAll(_ data: Data) throws -> (commands: [ControlCommand], unconsumed: Data) {
        var buffer = data
        var out: [ControlCommand] = []
        while !buffer.isEmpty {
            guard let (cmd, n) = try decodeOne(buffer) else { break }
            out.append(cmd)
            buffer = buffer.dropFirst(n)
        }
        return (out, buffer)
    }
}
