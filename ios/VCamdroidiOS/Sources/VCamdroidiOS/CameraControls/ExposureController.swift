import Foundation
import AVFoundation
import CoreMedia

/// Wraps `AVCaptureDevice.setExposureModeCustom(...)` and exposure
/// compensation. Handles the iPhone-specific clamping rules so the Windows
/// UI can send semantic values without worrying about device-specific
/// limits.
public final class ExposureController {
    public struct Capabilities {
        public let minISO: Float
        public let maxISO: Float
        public let minDurationSeconds: Float
        public let maxDurationSeconds: Float
        public let minCompensation: Float
        public let maxCompensation: Float
    }

    public let capabilities: Capabilities
    private let device: AVCaptureDevice
    private weak var capture: CaptureSessionManager?

    public init(device: AVCaptureDevice, capture: CaptureSessionManager) {
        self.device = device
        self.capture = capture
        let format = device.activeFormat
        self.capabilities = Capabilities(
            minISO: format.minISO,
            maxISO: format.maxISO,
            minDurationSeconds: Float(CMTimeGetSeconds(format.minExposureDuration)),
            maxDurationSeconds: Float(CMTimeGetSeconds(format.maxExposureDuration)),
            minCompensation: device.minExposureTargetBias,
            maxCompensation: device.maxExposureTargetBias
        )
    }

    public func apply(durationSeconds: Float, iso: Float) {
        let clampedDuration = CMTimeMakeWithSeconds(
            Double(durationSeconds.clamped(to: capabilities.minDurationSeconds...capabilities.maxDurationSeconds)),
            preferredTimescale: 1_000_000
        )
        let clampedISO = iso.clamped(to: capabilities.minISO...capabilities.maxISO)
        try? capture?.mutateDevice { device in
            device.setExposureModeCustom(duration: clampedDuration, iso: clampedISO, completionHandler: nil)
        }
    }

    public func apply(compensation: Float) {
        let value = compensation.clamped(to: capabilities.minCompensation...capabilities.maxCompensation)
        try? capture?.mutateDevice { device in
            device.setExposureTargetBias(value, completionHandler: nil)
        }
    }

    public func resetToAuto() {
        try? capture?.mutateDevice { device in
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.setExposureTargetBias(0, completionHandler: nil)
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
