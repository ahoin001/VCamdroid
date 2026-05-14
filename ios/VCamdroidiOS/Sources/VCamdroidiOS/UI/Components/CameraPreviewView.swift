import SwiftUI
import AVFoundation

/// Bridges `AVCaptureVideoPreviewLayer` into SwiftUI without copying any
/// frame data — the preview layer reads directly from the running capture
/// session.
public struct CameraPreviewView: UIViewRepresentable {
    public enum Gravity {
        case resizeAspectFill
        case resizeAspect
    }

    private let session: AVCaptureSession
    private let gravity: Gravity

    public init(session: AVCaptureSession, gravity: Gravity = .resizeAspectFill) {
        self.session = session
        self.gravity = gravity
    }

    public func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = (gravity == .resizeAspectFill) ? .resizeAspectFill : .resizeAspect
        return view
    }

    public func updateUIView(_ uiView: PreviewContainerView, context: Context) {
        uiView.previewLayer.videoGravity = (gravity == .resizeAspectFill) ? .resizeAspectFill : .resizeAspect
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
    }

    public final class PreviewContainerView: UIView {
        public override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        public var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
