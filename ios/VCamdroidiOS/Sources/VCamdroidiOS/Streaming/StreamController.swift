import Foundation
import AVFoundation
import CoreVideo
import CoreMedia

/// Top-level orchestrator. Owns the capture session, the encoder, the video
/// stream server, and the control channel. Wires their callbacks together so
/// none of the lower-level modules need to know about each other.
///
/// `StreamController` is the only class the UI talks to.
public final class StreamController: ObservableObject {

    @Published public private(set) var connectionState: ConnectionState = .disconnected
    @Published public private(set) var videoState: VideoState = .idle
    @Published public private(set) var configuration: StreamConfiguration = StreamConfiguration()
    @Published public private(set) var lastMetrics: StreamMetrics.Snapshot = .init(fps: 0, bitrateKbps: 0, droppedFrames: 0)
    @Published public private(set) var lastError: String?

    /// Lock-protected snapshot of the configuration for the hot path
    /// (encoder + capture callbacks running off the main thread). Kept in
    /// sync with `configuration` by every reconfigure call. Reading via
    /// `currentConfigurationSnapshot` never blocks on the main actor.
    private let configurationLock = NSLock()
    private var _configurationSnapshot: StreamConfiguration = StreamConfiguration()

    private func setConfiguration(_ value: StreamConfiguration) {
        configurationLock.lock()
        _configurationSnapshot = value
        configurationLock.unlock()
        Task { @MainActor in self.configuration = value }
    }

    private var currentConfigurationSnapshot: StreamConfiguration {
        configurationLock.lock()
        defer { configurationLock.unlock() }
        return _configurationSnapshot
    }

    public enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected(host: String, port: UInt16)
        case failed(String)
    }

    public enum VideoState: Equatable {
        case idle
        case listening
        case streaming
        case failed(String)
    }

    // Subsystems.
    private let capture: CaptureSessionManager
    private let encoder: VideoEncoder
    private let videoServer: VideoStreamServer
    private let controlChannel: ControlChannel
    private let metrics: StreamMetrics
    private let bonjour: BonjourPublisher
    private let portraitProcessor = PortraitEffectProcessor()
    private var abrController: AdaptiveBitrateController?
    private var useUsbLoopback = false

    /// Optional audio capture pipeline. Lazily created when Windows toggles
    /// `MIC_ENABLED` so apps that never enable the mic pay nothing.
    private var audioCapture: AudioCaptureManager?

    /// One-shot snapshot capture handler. The next decoded frame is grabbed,
    /// JPEG-encoded, and emitted via the control channel as a SNAPSHOT_RESPONSE.
    private var pendingSnapshot = false

    @Published public private(set) var studioModeEnabled: Bool = false
    @Published public private(set) var microphoneEnabled: Bool = false
    @Published public private(set) var currentBitrateKbps: Int = 0
    @Published public private(set) var hasTorch: Bool = false
    @Published public private(set) var portraitModeEnabled: Bool = false
    @Published public private(set) var portraitStrength: Int = 50

    // Camera controllers — populated in Phase 2.
    public private(set) var lensController: LensController?
    public private(set) var exposureController: ExposureController?
    public private(set) var whiteBalanceController: WhiteBalanceController?
    public private(set) var focusController: FocusController?
    public private(set) var stabilizationController: StabilizationController?

    public init(
        capture: CaptureSessionManager = CaptureSessionManager(),
        encoder: VideoEncoder = VTH264Encoder(),
        videoServer: VideoStreamServer = VideoStreamServer(),
        controlChannel: ControlChannel = ControlChannel(),
        metrics: StreamMetrics = StreamMetrics(),
        bonjour: BonjourPublisher = BonjourPublisher()
    ) {
        self.capture = capture
        self.encoder = encoder
        self.videoServer = videoServer
        self.controlChannel = controlChannel
        self.metrics = metrics
        self.bonjour = bonjour

        capture.delegate = self
        encoder.delegate = self
        controlChannel.commandHandler = { [weak self] cmd in self?.handle(command: cmd) }
        controlChannel.stateHandler = { [weak self] state in self?.handle(controlState: state) }
        videoServer.stateHandler = { [weak self] state in self?.handle(videoState: state) }
        metrics.snapshotHandler = { [weak self] snapshot in
            guard let self else { return }
            Task { @MainActor in self.lastMetrics = snapshot }
            if let kbps = self.abrController?.consume(snapshot: snapshot) {
                Task { @MainActor in self.currentBitrateKbps = kbps }
            }
        }
        // Initial snapshot.
        setConfiguration(configuration)
        disconnect()
    }

    // MARK: - Public API

    /// Auto mode: advertise on Bonjour and prefer USB loopback when available.
    public func startAutoDiscovery() {
        bonjour.start(deviceName: UIDevice.current.name)
    }

    public func stopAutoDiscovery() {
        bonjour.stop()
    }

    public func connectUsb() async {
        useUsbLoopback = true
        await connect(host: "127.0.0.1", controlPort: 6969, videoPort: 8554)
    }

    public func setPortraitMode(enabled: Bool, strength: Int) {
        let clamped = min(100, max(0, strength))
        portraitProcessor.setEnabled(enabled, strength: clamped)
        Task { @MainActor in
            self.portraitModeEnabled = enabled
            self.portraitStrength = clamped
        }
        reconfigureNoRestart {
            $0.portraitModeEnabled = enabled
            $0.portraitStrength = clamped
        }
    }

    public func setExposureCompensation(_ bias: Float) {
        exposureController?.apply(compensation: bias)
    }

    public func setWhiteBalance(temperatureK: Float, tint: Float) {
        whiteBalanceController?.apply(temperatureK: temperatureK, tint: tint)
    }

    /// Brings up capture preview and the video listener, then dials the
    /// Windows control endpoint. Once Windows ACTIVATEs us, encoded frames
    /// start flowing automatically.
    public func connect(host: String, controlPort: UInt16 = 6969, videoPort: UInt16 = 8554) async {
        await MainActor.run { self.connectionState = .connecting }
        guard await CameraAuthorization.ensureGranted() else {
            await MainActor.run {
                self.connectionState = .failed("Camera permission denied")
                self.lastError = "Camera permission denied"
            }
            return
        }

        let snapshot = currentConfigurationSnapshot
        do {
            try capture.start(configuration: snapshot)
            try videoServer.start()
        } catch {
            await MainActor.run {
                self.videoState = .failed(error.localizedDescription)
                self.lastError = error.localizedDescription
            }
        }

        attachCameraControllers()

        let descriptor = await buildDescriptor(videoPort: videoPort)
        controlChannel.connect(host: host, port: controlPort, descriptor: descriptor)
        if !bonjour.isPublishing {
            bonjour.start(deviceName: descriptor.name)
        }
        metrics.start()

        await MainActor.run {
            self.connectionState = .connected(host: host, port: controlPort)
        }
    }

    public func disconnect() {
        controlChannel.disconnect()
        videoServer.stop()
        capture.stop()
        encoder.teardown()
        metrics.stop()
        bonjour.stop()
        audioCapture?.stop()
        audioCapture = nil
        abrController = nil
        pendingSnapshot = false
        useUsbLoopback = false
        portraitProcessor.setEnabled(false, strength: 0)
        lensController = nil
        exposureController = nil
        whiteBalanceController = nil
        focusController = nil
        stabilizationController = nil
        Task { @MainActor in
            self.connectionState = .disconnected
            self.videoState = .idle
            self.microphoneEnabled = false
        }
    }

    /// Used by the SwiftUI preview to read the underlying `AVCaptureSession`.
    public var captureSession: AVCaptureSession { capture.captureSession }

    // MARK: - Command dispatch

    private func handle(command: ControlCommand) {
        Log.debug("control", "Received \(command)")
        switch command {
        case .activation(let config):
            applyActivation(config: config)
        case .setResolution(let w, let h):
            reconfigure { $0.width = w; $0.height = h }
        case .swapCamera:
            reconfigure { $0.useBackCamera.toggle() }
        case .rotate(_):
            // Rotation is a Windows-side concern (handled in the desktop preview).
            // Nothing for the phone to do; we always send portrait-orientation video.
            break
        case .setBitrate(let kbps):
            encoder.updateBitrate(kbps)
        case .setAdaptiveBitrate(let lo, let hi):
            reconfigureNoRestart {
                $0.adaptiveBitrate = true
                $0.minBitrateKbps = lo
                $0.maxBitrateKbps = hi
            }
            configureABR()
        case .setStabilization(let on):
            reconfigure { $0.stabilizationEnabled = on }
        case .setFlash(let on):
            setTorch(on)
        case .setPortraitMode(let enabled, let strength):
            setPortraitMode(enabled: enabled, strength: strength)
        case .setFocusMode(let mode):
            focusController?.apply(mode: mode)
        case .setCodec(let h265):
            reconfigure { $0.h265Enabled = h265 }
        case .setFps(let fps):
            reconfigure { $0.fps = fps }
        case .setZoom(let factor):
            lensController?.setZoom(factor: factor)
        case .flip(_):
            // Flip is a Windows-side rendering toggle; passed through for parity.
            break

        // Phase 2 commands
        case .setLensZoom(let factor):
            lensController?.setZoom(factor: factor)
        case .setExposure(let duration, let iso):
            exposureController?.apply(durationSeconds: duration, iso: iso)
        case .setWhiteBalance(let temp, let tint):
            whiteBalanceController?.apply(temperatureK: temp, tint: tint)
        case .setExposureCompensation(let bias):
            exposureController?.apply(compensation: bias)
        case .setStabilizationMode(let mode):
            stabilizationController?.apply(mode: mode)
        case .setFocusLock(let lensPos):
            focusController?.apply(lensPosition: lensPos)
        case .tapToFocus(let x, let y):
            focusController?.focusAt(x: x, y: y)
        case .resetCameraToAuto:
            exposureController?.resetToAuto()
            whiteBalanceController?.resetToAuto()
            focusController?.resetToAuto()

        // Phase 3 / 4 commands handled elsewhere
        case .setStudioMode(let enabled):
            Task { @MainActor in self.studioModeEnabled = enabled }
        case .setMicrophone(let enabled):
            toggleMicrophone(enabled: enabled)
        case .snapshotRequest:
            requestSnapshot()
        case .correctionFilter(_, _), .effectFilter(_):
            // Filters are applied Windows-side in the GPU pipeline; phone is a pass-through.
            break
        case .unknown(let opcode, _):
            Log.warning("control", "Ignoring unknown opcode 0x\(String(opcode, radix: 16))")
        }
    }

    private func applyActivation(config: StreamConfiguration) {
        setConfiguration(config)
        do {
            try capture.updateConfiguration(config)
            try encoder.configure(makeEncoderConfig(from: config))
            encoder.requestKeyframe()
            attachCameraControllers()
            applyTorchFromConfiguration(config)
            portraitProcessor.setEnabled(config.portraitModeEnabled, strength: config.portraitStrength)
            Task { @MainActor in
                self.portraitModeEnabled = config.portraitModeEnabled
                self.portraitStrength = config.portraitStrength
            }
            configureABR()
        } catch {
            Log.error("stream", "Activation failed: \(error.localizedDescription)")
            Task { @MainActor in self.lastError = error.localizedDescription }
        }
    }

    /// Rebuilds the ABR controller so it always reflects the freshly applied
    /// `StreamConfiguration`. Cheap to call on every reconfigure.
    private func configureABR() {
        let cfg = currentConfigurationSnapshot
        let policy: AdaptiveBitrateController.Policy = cfg.adaptiveBitrate
            ? .adaptive(minKbps: cfg.minBitrateKbps, maxKbps: cfg.maxBitrateKbps)
            : .staticBitrate(kbps: cfg.bitrateKbps)
        if abrController == nil {
            abrController = AdaptiveBitrateController(encoder: encoder, policy: policy, targetFps: cfg.fps)
        } else {
            abrController?.updatePolicy(policy, targetFps: cfg.fps)
        }
        let initial = cfg.adaptiveBitrate ? cfg.maxBitrateKbps : cfg.bitrateKbps
        Task { @MainActor in self.currentBitrateKbps = initial }
    }

    private func toggleMicrophone(enabled: Bool) {
        if enabled {
            if audioCapture == nil { audioCapture = AudioCaptureManager() }
            do {
                try audioCapture?.start()
                Task { @MainActor in self.microphoneEnabled = true }
            } catch {
                Log.error("audio", "\(error.localizedDescription)")
            }
        } else {
            audioCapture?.stop()
            Task { @MainActor in self.microphoneEnabled = false }
        }
    }

    private func requestSnapshot() {
        // Force a keyframe so the next emitted NAL is decodable on its own;
        // the actual JPEG capture happens in the next pixel-buffer delivery.
        pendingSnapshot = true
        encoder.requestKeyframe()
    }

    private func reconfigure(_ mutate: (inout StreamConfiguration) -> Void) {
        var snapshot = currentConfigurationSnapshot
        mutate(&snapshot)
        applyActivation(config: snapshot)
    }

    private func reconfigureNoRestart(_ mutate: (inout StreamConfiguration) -> Void) {
        var snapshot = currentConfigurationSnapshot
        mutate(&snapshot)
        setConfiguration(snapshot)
    }

    // MARK: - Encoder config

    private func makeEncoderConfig(from streamConfig: StreamConfiguration) -> VideoEncoderConfig {
        VideoEncoderConfig(
            codec: streamConfig.h265Enabled ? .h265 : .h264,
            width: streamConfig.width,
            height: streamConfig.height,
            fps: streamConfig.fps,
            bitrateBps: streamConfig.bitrateKbps * 1_000,
            keyframeIntervalFrames: max(streamConfig.fps, 30)
        )
    }

    private func makeHeader(from streamConfig: StreamConfiguration) -> VideoStreamHeader {
        VideoStreamHeader(
            codec: streamConfig.h265Enabled ? .h265 : .h264,
            width: UInt16(streamConfig.width),
            height: UInt16(streamConfig.height),
            fps: UInt8(min(255, streamConfig.fps))
        )
    }

    // MARK: - Descriptor

    private func setTorch(_ on: Bool) {
        capture.sessionQueueAsync {
            do {
                try self.capture.mutateDevice { device in
                    guard device.hasTorch else { return }
                    if on {
                        try device.setTorchModeOn(level: 1.0)
                    } else {
                        device.torchMode = .off
                    }
                }
            } catch {
                Log.error("torch", error.localizedDescription)
            }
        }
    }

    private func applyTorchFromConfiguration(_ config: StreamConfiguration) {
        setTorch(config.flashEnabled)
    }

    private func buildDescriptor(videoPort: UInt16) async -> DeviceDescriptor {
        let (back, front) = capture.enumerateSupportedResolutions()
        let host = useUsbLoopback ? "127.0.0.1" : LocalHost.bestRoutableAddress()
        let url = "vcmd://\(host):\(videoPort)/v1?codec=h264"
        let name = await UIDevice.bestDisplayName
        return DeviceDescriptor(
            name: name,
            url: url,
            frontResolutions: front,
            backResolutions: back,
            filters: []
        )
    }

    // MARK: - Camera controllers

    private func attachCameraControllers() {
        guard let device = capture.currentDevice else { return }
        Task { @MainActor in self.hasTorch = device.hasTorch && device.position == .back }
        lensController = LensController(device: device, capture: capture)
        exposureController = ExposureController(device: device, capture: capture)
        whiteBalanceController = WhiteBalanceController(device: device, capture: capture)
        focusController = FocusController(device: device, capture: capture)
        stabilizationController = StabilizationController(capture: capture)
    }

    private func handle(controlState: ControlChannel.State) {
        switch controlState {
        case .idle:
            Task { @MainActor in self.connectionState = .disconnected }
        case .connecting:
            Task { @MainActor in self.connectionState = .connecting }
        case .connected:
            // Already set in connect()
            break
        case .failed(let reason):
            Task { @MainActor in
                self.connectionState = .failed(reason)
                self.lastError = reason
            }
        }
    }

    private func handle(videoState: VideoStreamServer.State) {
        switch videoState {
        case .stopped:    Task { @MainActor in self.videoState = .idle } 
        case .listening:  Task { @MainActor in self.videoState = .listening }
        case .streaming:
            Task { @MainActor in self.videoState = .streaming }
            // A new Windows client just connected — force a keyframe so they
            // get parameter sets immediately.
            encoder.requestKeyframe()
        case .failed(let reason):
            Task { @MainActor in self.videoState = .failed(reason) }
        }
    }
}

// MARK: - Capture / encoder bridging

extension StreamController: CaptureSessionDelegate {
    public func captureSession(_ session: CaptureSessionManager, didOutput pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        let frame = portraitProcessor.process(pixelBuffer)
        if pendingSnapshot {
            pendingSnapshot = false
            if let payload = SnapshotResponse.makePayload(from: frame) {
                controlChannel.send(payload)
            }
        }
        guard videoServer.hasSubscriber else { return }
        encoder.encode(pixelBuffer: frame, presentationTime: presentationTime, forceKeyframe: false)
    }

    public func captureSession(_ session: CaptureSessionManager, didFailWith error: Error) {
        Log.error("capture", "\(error.localizedDescription)")
        Task { @MainActor in self.lastError = error.localizedDescription }
    }
}

extension StreamController: VideoEncoderDelegate {
    public func videoEncoder(_ encoder: VideoEncoder, didEmit nal: Data, isParameterSet: Bool, isKeyframe: Bool, presentationTime: CMTime) {
        let header = makeHeader(from: currentConfigurationSnapshot)
        videoServer.send(nal: nal, header: header, isParameterSet: isParameterSet, isKeyframe: isKeyframe)
        metrics.recordFrame(byteSize: nal.count)
    }

    public func videoEncoder(_ encoder: VideoEncoder, didFailWith error: Error) {
        Log.error("encoder", "\(error.localizedDescription)")
        Task { @MainActor in self.lastError = error.localizedDescription }
    }
}

// MARK: - Helpers

import UIKit
private extension UIDevice {
    static var bestDisplayName: String {
        get async {
            await MainActor.run { UIDevice.current.name }
        }
    }
}

private enum LocalHost {
    /// Returns the device's most likely LAN IP — used to populate the URL
    /// in the descriptor so the Windows side can connect back to us over
    /// Wi-Fi. For USB tunneling Windows substitutes the loopback address.
    static func bestRoutableAddress() -> String {
        var address = "127.0.0.1"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return address }
        defer { freeifaddrs(ifaddr) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let p = pointer {
            let name = String(cString: p.pointee.ifa_name)
            let addrFamily = p.pointee.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET), name.hasPrefix("en") {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(p.pointee.ifa_addr, socklen_t(p.pointee.ifa_addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                    address = String(cString: hostname)
                    break
                }
            }
            pointer = p.pointee.ifa_next
        }
        return address
    }
}
