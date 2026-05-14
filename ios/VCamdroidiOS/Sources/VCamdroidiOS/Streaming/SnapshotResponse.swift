import Foundation
import CoreImage
import CoreVideo
import UIKit

/// Builds the binary payload for a SNAPSHOT_RESPONSE control message.
///
/// Wire layout (matches `docs/PROTOCOL.md`):
///   u8  opcode       = 0x40 (SnapshotResponse)
///   u32 jpegLength   (big-endian)
///   ... JPEG bytes
public enum SnapshotResponse {
    public static let opcode: UInt8 = 0x40

    /// Renders the supplied CVPixelBuffer to JPEG (quality 0.85) and packages
    /// it into a transport-ready Data blob. Returns `nil` if rendering fails.
    public static func makePayload(from pixelBuffer: CVPixelBuffer, quality: CGFloat = 0.85) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        let uiImage = UIImage(cgImage: cgImage)
        guard let jpeg = uiImage.jpegData(compressionQuality: quality) else { return nil }

        var payload = Data()
        payload.append(opcode)
        let len = UInt32(jpeg.count)
        var beLen = len.bigEndian
        withUnsafeBytes(of: &beLen) { payload.append(contentsOf: $0) }
        payload.append(jpeg)
        return payload
    }
}
