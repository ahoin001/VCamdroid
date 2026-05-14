import Foundation
import AVFoundation

/// Maps temperature / tint values from the Windows UI into the device's
/// per-channel gain space (R/G/B) using AVFoundation's helper. We always
/// re-clamp the gains because pushing past `maxWhiteBalanceGain` produces
/// undefined behavior on some iPhones.
public final class WhiteBalanceController {
    public struct Capabilities {
        public let maxGain: Float
        public let minTemperatureK: Float = 2_500
        public let maxTemperatureK: Float = 10_000
        public let minTint: Float = -150
        public let maxTint: Float = 150
    }

    public let capabilities: Capabilities
    private let device: AVCaptureDevice
    private weak var capture: CaptureSessionManager?

    public init(device: AVCaptureDevice, capture: CaptureSessionManager) {
        self.device = device
        self.capture = capture
        self.capabilities = Capabilities(maxGain: device.maxWhiteBalanceGain)
    }

    public func apply(temperatureK: Float, tint: Float) {
        let temp = temperatureK.clamped(to: capabilities.minTemperatureK...capabilities.maxTemperatureK)
        let tnt = tint.clamped(to: capabilities.minTint...capabilities.maxTint)
        let tempAndTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: temp, tint: tnt)

        try? capture?.mutateDevice { device in
            let rawGains = device.deviceWhiteBalanceGains(for: tempAndTint)
            let clamped = self.clamp(rawGains)
            device.setWhiteBalanceModeLocked(with: clamped, completionHandler: nil)
        }
    }

    public func resetToAuto() {
        try? capture?.mutateDevice { device in
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
        }
    }

    private func clamp(_ gains: AVCaptureDevice.WhiteBalanceGains) -> AVCaptureDevice.WhiteBalanceGains {
        let cap = capabilities.maxGain
        return AVCaptureDevice.WhiteBalanceGains(
            redGain: gains.redGain.clamped(to: 1.0...cap),
            greenGain: gains.greenGain.clamped(to: 1.0...cap),
            blueGain: gains.blueGain.clamped(to: 1.0...cap)
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
