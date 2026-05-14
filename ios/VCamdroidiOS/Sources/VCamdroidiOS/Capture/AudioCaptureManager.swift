import Foundation
import AVFoundation

/// Optional microphone capture. When the Windows side toggles the
/// `MIC_ENABLED` opcode this manager spins up an `AVCaptureAudioDataOutput`,
/// hands raw `CMSampleBuffer`s to the delegate, and stops when disabled.
///
/// AAC encoding + transport interleaving is intentionally not done in this
/// class — keeping audio encode and transport separate lets us evolve the
/// audio side (AAC over QUIC, Opus, ...) without disturbing the video path.
/// The companion `AudioStreamWriter` (TODO) will hook in via the delegate.
public protocol AudioCaptureDelegate: AnyObject {
    func audioCapture(_ capture: AudioCaptureManager, didOutput sampleBuffer: CMSampleBuffer)
    func audioCapture(_ capture: AudioCaptureManager, didFailWith error: Error)
}

public final class AudioCaptureManager: NSObject {
    public weak var delegate: AudioCaptureDelegate?

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "vcamdroid.audio.capture", qos: .userInitiated)
    private let dataOutput = AVCaptureAudioDataOutput()

    public override init() {
        super.init()
        dataOutput.setSampleBufferDelegate(self, queue: queue)
    }

    public func start() throws {
        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw NSError(domain: "VCamdroid", code: -20, userInfo: [NSLocalizedDescriptionKey: "No microphone available"])
        }
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        for existing in session.inputs { session.removeInput(existing) }
        if session.canAddInput(input) { session.addInput(input) }
        if !session.outputs.contains(dataOutput) {
            if session.canAddOutput(dataOutput) { session.addOutput(dataOutput) }
        }
        session.commitConfiguration()
        if !session.isRunning { session.startRunning() }
    }

    public func stop() {
        if session.isRunning { session.stopRunning() }
    }
}

extension AudioCaptureManager: AVCaptureAudioDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        delegate?.audioCapture(self, didOutput: sampleBuffer)
    }
}
