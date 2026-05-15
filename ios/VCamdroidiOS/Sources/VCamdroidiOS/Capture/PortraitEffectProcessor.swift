import Foundation
import CoreImage
import CoreVideo
import Vision

/// Applies Camo-style portrait bokeh: sharp subject, blurred background.
/// Runs on a dedicated queue; safe to call from the capture output callback.
public final class PortraitEffectProcessor {
    private let queue = DispatchQueue(label: "vcamdroid.portrait.fx", qos: .userInitiated)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let segmentationRequest = VNGeneratePersonSegmentationRequest()

    private var enabled = false
    private var strength: Float = 0.5

    public init() {
        segmentationRequest.qualityLevel = .balanced
        segmentationRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8
    }

    public func setEnabled(_ on: Bool, strength percent: Int) {
        queue.async {
            self.enabled = on
            self.strength = Float(min(100, max(0, percent))) / 100.0
        }
    }

    /// Returns the input buffer unchanged when disabled or segmentation fails.
    public func process(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer {
        var result = pixelBuffer
        queue.sync {
            guard enabled, strength > 0.01 else { return }
            if let processed = applyBokeh(to: pixelBuffer) {
                result = processed
            }
        }
        return result
    }

    private func applyBokeh(to pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([segmentationRequest])
        } catch {
            return nil
        }

        guard let observation = segmentationRequest.results?.first else {
            return nil
        }

        let source = CIImage(cvPixelBuffer: pixelBuffer)
        let mask = CIImage(cvPixelBuffer: observation.pixelBuffer)
        let scaledMask = mask.transformed(by: CGAffineTransform(
            scaleX: CGFloat(CVPixelBufferGetWidth(pixelBuffer)) / CGFloat(CVPixelBufferGetWidth(observation.pixelBuffer)),
            y: CGFloat(CVPixelBufferGetHeight(pixelBuffer)) / CGFloat(CVPixelBufferGetHeight(observation.pixelBuffer))
        ))

        let blurRadius = 4.0 + Double(strength) * 18.0
        let blurred = source.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [
            kCIInputRadiusKey: blurRadius
        ]).cropped(to: source.extent)

        let matte = scaledMask.applyingFilter("CIMaskToAlpha")
        let composite = blurred.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputImageKey: source,
            kCIInputBackgroundImageKey: blurred,
            kCIInputMaskImageKey: matte
        ])

        var out: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            CVPixelBufferGetWidth(pixelBuffer),
            CVPixelBufferGetHeight(pixelBuffer),
            CVPixelBufferGetPixelFormatType(pixelBuffer),
            attrs as CFDictionary,
            &out
        )
        guard let output = out else { return nil }
        ciContext.render(composite, to: output)
        return output
    }
}
