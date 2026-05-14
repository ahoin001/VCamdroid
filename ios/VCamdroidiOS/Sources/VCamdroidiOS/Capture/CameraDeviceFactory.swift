import Foundation
import AVFoundation

/// Builds the best `AVCaptureDevice` for a given camera role on the current
/// hardware. Prefers virtual multi-camera devices (triple / dual / dualWide)
/// so the zoom slider can fan out across all available lenses without
/// session restarts. Falls back gracefully on older iPhones / iPads.
public enum CameraDeviceFactory {

    public enum Role {
        case back
        case front
    }

    public static func makeDevice(for role: Role) -> AVCaptureDevice? {
        switch role {
        case .back:
            return bestBackDevice()
        case .front:
            return bestFrontDevice()
        }
    }

    // MARK: - Internal

    private static func bestBackDevice() -> AVCaptureDevice? {
        let preferred: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInWideAngleCamera
        ]
        for type in preferred {
            if let device = AVCaptureDevice.default(type, for: .video, position: .back) {
                Log.info("capture", "Selected back device: \(type.rawValue) (\(device.localizedName))")
                return device
            }
        }
        return AVCaptureDevice.default(for: .video)
    }

    private static func bestFrontDevice() -> AVCaptureDevice? {
        let preferred: [AVCaptureDevice.DeviceType] = [
            .builtInTrueDepthCamera,
            .builtInWideAngleCamera
        ]
        for type in preferred {
            if let device = AVCaptureDevice.default(type, for: .video, position: .front) {
                Log.info("capture", "Selected front device: \(type.rawValue) (\(device.localizedName))")
                return device
            }
        }
        return nil
    }
}
