import Foundation
import AVFoundation
import CoreGraphics

/// Drives autofocus, tap-to-focus, and manual lens-position locks.
///
/// `lensPosition` on AVFoundation is a normalized 0.0 (near) → 1.0 (far)
/// value. We avoid waiting for the completion handler so the Windows UI's
/// slider stays responsive — the next `apply(...)` simply pre-empts the
/// previous one.
public final class FocusController {
    private let device: AVCaptureDevice
    private weak var capture: CaptureSessionManager?

    public init(device: AVCaptureDevice, capture: CaptureSessionManager) {
        self.device = device
        self.capture = capture
    }

    public func apply(mode: FocusMode) {
        try? capture?.mutateDevice { device in
            switch mode {
            case .auto:
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
            case .manual:
                if device.isFocusModeSupported(.locked) {
                    device.focusMode = .locked
                }
            }
        }
    }

    public func apply(lensPosition: Float?) {
        try? capture?.mutateDevice { device in
            if let position = lensPosition, device.isLockingFocusWithCustomLensPositionSupported {
                let clamped = max(0.0, min(1.0, position))
                device.setFocusModeLocked(lensPosition: clamped, completionHandler: nil)
            } else if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
        }
    }

    public func focusAt(x: Float, y: Float) {
        try? capture?.mutateDevice { device in
            let point = CGPoint(x: CGFloat(x), y: CGFloat(y))
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
            }
            if device.isFocusModeSupported(.autoFocus) {
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
            }
            if device.isExposureModeSupported(.autoExpose) {
                device.exposureMode = .autoExpose
            }
        }
    }

    public func resetToAuto() {
        apply(mode: .auto)
    }
}
