import Foundation
import AVFoundation

/// Tweaks `AVCaptureConnection.preferredVideoStabilizationMode` on the active
/// data output. Cinematic / cinematic-extended modes are only available on
/// Pro iPhones for back cameras at high resolution — we fall back to
/// `.standard` if the requested mode isn't supported.
public final class StabilizationController {
    private weak var capture: CaptureSessionManager?

    public init(capture: CaptureSessionManager) {
        self.capture = capture
    }

    public func apply(mode: StabilizationMode) {
        guard let capture else { return }
        let session = capture.captureSession
        guard let connection = session.outputs
            .compactMap({ $0.connections.first(where: { $0.isVideoStabilizationSupported }) })
            .first else { return }

        let avMode: AVCaptureVideoStabilizationMode
        switch mode {
        case .off:                avMode = .off
        case .standard:           avMode = .standard
        case .cinematic:          avMode = .cinematic
        case .cinematicExtended:
            if #available(iOS 17.0, *) {
                avMode = .cinematicExtended
            } else {
                avMode = .cinematic
            }
        }
        connection.preferredVideoStabilizationMode = avMode
    }
}
