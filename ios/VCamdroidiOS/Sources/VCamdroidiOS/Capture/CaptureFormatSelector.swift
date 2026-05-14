import Foundation
import AVFoundation

/// Picks the best `AVCaptureDevice.Format` for a requested resolution / fps.
/// We bias towards the lowest-overhead `420v` (full-range 4:2:0 NV12) pixel
/// format because that is what the encoder hardware natively consumes — any
/// other format would force a CPU-side colorspace conversion which is the
/// single biggest source of latency / battery drain in this kind of app.
public enum CaptureFormatSelector {

    public struct Selection {
        public let format: AVCaptureDevice.Format
        public let frameRateRange: AVFrameRateRange
    }

    public static func selectFormat(
        for device: AVCaptureDevice,
        targetWidth: Int,
        targetHeight: Int,
        targetFps: Int
    ) -> Selection? {
        var best: (Selection, Int)? = nil // (selection, distance)

        for format in device.formats {
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let w = Int(dims.width)
            let h = Int(dims.height)

            // Prefer formats whose pixel format is 420v (full-range) or 420f.
            let mediaSubType = CMFormatDescriptionGetMediaSubType(format.formatDescription)
            let isPreferredPixelFormat = (
                mediaSubType == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
                mediaSubType == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            )
            guard isPreferredPixelFormat else { continue }

            for range in format.videoSupportedFrameRateRanges {
                guard Double(targetFps) >= range.minFrameRate,
                      Double(targetFps) <= range.maxFrameRate else { continue }

                // Distance metric prioritises area match, then fps headroom.
                let areaDelta = abs(w * h - targetWidth * targetHeight)
                let fpsHeadroom = Int(range.maxFrameRate) - targetFps
                let distance = areaDelta * 1000 + max(0, -fpsHeadroom) * 10_000

                let candidate = Selection(format: format, frameRateRange: range)
                if best == nil || distance < best!.1 {
                    best = (candidate, distance)
                }
            }
        }

        return best?.0
    }
}
