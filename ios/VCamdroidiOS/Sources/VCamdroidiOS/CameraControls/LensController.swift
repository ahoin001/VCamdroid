import Foundation
import AVFoundation

/// Operates the continuous zoom slider on a back camera that may be a
/// virtual multi-lens device (`builtInTripleCamera`, `builtInDualWideCamera`,
/// etc.). Setting `videoZoomFactor` between the documented
/// `virtualDeviceSwitchOverVideoZoomFactors` thresholds tells AVFoundation
/// to seamlessly fade between the underlying physical lenses, which is the
/// premium UX users expect from "5x telephoto" / "0.5x ultra-wide" sliders.
public final class LensController {
    public struct Capabilities {
        public let minZoomFactor: CGFloat
        public let maxZoomFactor: CGFloat
        /// Optical / virtual device switchover thresholds (e.g. [2.0, 5.0]
        /// on iPhone 16 Pro). Useful for showing lens labels in the UI.
        public let virtualSwitchoverFactors: [CGFloat]
    }

    public let capabilities: Capabilities
    private let device: AVCaptureDevice
    private weak var capture: CaptureSessionManager?

    public init(device: AVCaptureDevice, capture: CaptureSessionManager) {
        self.device = device
        self.capture = capture
        self.capabilities = Capabilities(
            minZoomFactor: device.minAvailableVideoZoomFactor,
            maxZoomFactor: device.maxAvailableVideoZoomFactor,
            virtualSwitchoverFactors: device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        )
    }

    /// Animates to a new zoom factor, clamped into the device's supported
    /// range. We use a smooth ramp so users get the same "buttery zoom" they
    /// see in Camera.app rather than an abrupt jump.
    public func setZoom(factor: Float) {
        let clamped = CGFloat(factor)
            .clamped(to: capabilities.minZoomFactor...capabilities.maxZoomFactor)
        try? capture?.mutateDevice { device in
            device.ramp(toVideoZoomFactor: clamped, withRate: 8.0)
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
