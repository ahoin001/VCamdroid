import Foundation
import AVFoundation
import CoreMedia
import CoreVideo

/// Authorization helper. Wraps `AVCaptureDevice.requestAccess` so the
/// orchestrator can `await` permission without dragging delegates around.
public enum CameraAuthorization {
    public static func ensureGranted() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized: return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }
}

public protocol CaptureSessionDelegate: AnyObject {
    /// Called from the capture queue. Pixel buffers are guaranteed to be
    /// IOSurface-backed and so can be fed to `VTCompressionSession` without
    /// copying.
    func captureSession(_ session: CaptureSessionManager, didOutput pixelBuffer: CVPixelBuffer, presentationTime: CMTime)
    func captureSession(_ session: CaptureSessionManager, didFailWith error: Error)
}

public final class CaptureSessionManager: NSObject {
    public weak var delegate: CaptureSessionDelegate?

    /// Current `AVCaptureDevice`. Exposed so the camera controllers (zoom,
    /// exposure, white balance, focus, stabilization) can operate against it.
    public private(set) var currentDevice: AVCaptureDevice?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "vcamdroid.capture.session", qos: .userInitiated)
    private let outputQueue = DispatchQueue(label: "vcamdroid.capture.output", qos: .userInteractive)
    private let dataOutput = AVCaptureVideoDataOutput()

    private var role: CameraDeviceFactory.Role = .back

    public override init() {
        super.init()
        dataOutput.alwaysDiscardsLateVideoFrames = true
        dataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        dataOutput.setSampleBufferDelegate(self, queue: outputQueue)
    }

    /// Returns `(back, front)` lists of resolutions the host hardware can
    /// produce for the encoder pipeline. Used for the `DeviceDescriptor`.
    public func enumerateSupportedResolutions() -> (back: [DeviceDescriptor.Resolution], front: [DeviceDescriptor.Resolution]) {
        let back = supportedResolutions(role: .back)
        let front = supportedResolutions(role: .front)
        return (back, front)
    }

    /// Returns the live `AVCaptureSession` so the preview view can attach a
    /// `AVCaptureVideoPreviewLayer` to it.
    public var captureSession: AVCaptureSession { session }

    public func start(configuration: StreamConfiguration) throws {
        sessionQueue.sync {
            do {
                try applyConfiguration(configuration)
                if !session.isRunning { session.startRunning() }
            } catch {
                delegate?.captureSession(self, didFailWith: error)
            }
        }
    }

    public func stop() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    public func switchCamera(to newRole: CameraDeviceFactory.Role, configuration: StreamConfiguration) throws {
        sessionQueue.sync {
            role = newRole
            do {
                try applyConfiguration(configuration)
            } catch {
                delegate?.captureSession(self, didFailWith: error)
            }
        }
    }

    public func updateConfiguration(_ configuration: StreamConfiguration) throws {
        sessionQueue.sync {
            do {
                try applyConfiguration(configuration)
            } catch {
                delegate?.captureSession(self, didFailWith: error)
            }
        }
    }

    /// Performs a lock-protected mutation of the current device. Used by the
    /// camera controllers; centralizing keeps lock semantics consistent.
    public func mutateDevice(_ mutation: (AVCaptureDevice) throws -> Void) throws {
        guard let device = currentDevice else { return }
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        try mutation(device)
    }

    // MARK: - Internal

    private func applyConfiguration(_ configuration: StreamConfiguration) throws {
        role = configuration.useBackCamera ? .back : .front
        guard let device = CameraDeviceFactory.makeDevice(for: role) else {
            throw NSError(domain: "VCamdroid", code: -10, userInfo: [NSLocalizedDescriptionKey: "No camera available for role \(role)"])
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // Replace inputs.
        for input in session.inputs { session.removeInput(input) }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw NSError(domain: "VCamdroid", code: -11, userInfo: [NSLocalizedDescriptionKey: "Cannot add capture input"])
        }
        session.addInput(input)

        // Make sure our output is attached.
        if !session.outputs.contains(dataOutput) {
            if session.canAddOutput(dataOutput) {
                session.addOutput(dataOutput)
            } else {
                throw NSError(domain: "VCamdroid", code: -12, userInfo: [NSLocalizedDescriptionKey: "Cannot add capture output"])
            }
        }

        // Lock down format / fps.
        if let selection = CaptureFormatSelector.selectFormat(
            for: device,
            targetWidth: configuration.width,
            targetHeight: configuration.height,
            targetFps: configuration.fps
        ) {
            try device.lockForConfiguration()
            device.activeFormat = selection.format
            let duration = CMTimeMake(value: 1, timescale: Int32(configuration.fps))
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            // Default stabilization here; controllers can override per command.
            if let connection = dataOutput.connection(with: .video), connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = configuration.stabilizationEnabled ? .standard : .off
            }
            // Tell the connection to use the natural portrait orientation by
            // default. The Windows UI manages rotation downstream.
            if let connection = dataOutput.connection(with: .video), connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            // Mirror the front camera so the operator sees themselves naturally.
            if let connection = dataOutput.connection(with: .video), connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = (role == .front)
            }
            device.unlockForConfiguration()
        }

        currentDevice = device
    }

    private func supportedResolutions(role: CameraDeviceFactory.Role) -> [DeviceDescriptor.Resolution] {
        guard let device = CameraDeviceFactory.makeDevice(for: role) else { return [] }
        var seen = Set<String>()
        var resolutions: [DeviceDescriptor.Resolution] = []
        // We surface canonical resolutions only — the Windows UI lists discrete
        // entries, so reporting every minor variant would clutter the dropdown.
        let canonical: [(Int, Int)] = [(640, 480), (1280, 720), (1920, 1080), (3840, 2160)]
        for (w, h) in canonical {
            let supports = device.formats.contains { format in
                let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                return Int(dims.width) == w && Int(dims.height) == h
            }
            let key = "\(w)x\(h)"
            if supports, !seen.contains(key) {
                resolutions.append(.init(width: w, height: h))
                seen.insert(key)
            }
        }
        return resolutions
    }
}

extension CaptureSessionManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        delegate?.captureSession(self, didOutput: pixelBuffer, presentationTime: pts)
    }
}
