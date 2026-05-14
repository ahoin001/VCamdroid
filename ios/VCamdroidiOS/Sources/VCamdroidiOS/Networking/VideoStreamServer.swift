import Foundation
import Network

/// TCP server that accepts exactly one Windows client at a time on port 8554
/// and streams length-prefixed H.264 / H.265 NAL units.
///
/// The server is intentionally simple: only one Windows client owns a phone
/// at a time. Subsequent connections are accepted but immediately cancelled
/// so the existing session is not disturbed.
public final class VideoStreamServer {
    public enum State: Equatable {
        case stopped
        case listening
        case streaming
        case failed(String)
    }

    public var stateHandler: ((State) -> Void)?

    public private(set) var state: State = .stopped {
        didSet {
            guard oldValue != state else { return }
            let snapshot = state
            callbackQueue.async { [stateHandler] in stateHandler?(snapshot) }
        }
    }

    private let port: NWEndpoint.Port
    private let workQueue = DispatchQueue(label: "vcamdroid.video.io", qos: .userInteractive)
    private let callbackQueue: DispatchQueue
    private var listener: NWListener?
    private var activeConnection: NWConnection?
    private var headerSent = false

    /// Outstanding bytes the underlying socket hasn't drained yet. Used as a
    /// crude backpressure signal so we can drop non-keyframe NALs before the
    /// kernel queue grows unbounded under a stalled receiver. 4 MB ≈ ~30 ms
    /// of headroom at 1080p30 high bitrate — plenty for healthy networks, an
    /// early warning under congestion.
    private var pendingSendBytes: Int = 0
    private let pendingSendLock = NSLock()
    private static let pendingSendHighWaterMark = 4 * 1024 * 1024

    public init(port: UInt16 = 8554, callbackQueue: DispatchQueue = .main) {
        self.port = NWEndpoint.Port(rawValue: port) ?? .init(integerLiteral: 8554)
        self.callbackQueue = callbackQueue
    }

    /// Begins listening. Idempotent.
    public func start() throws {
        guard listener == nil else { return }

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        tcpOptions.enableKeepalive = true

        let params = NWParameters(tls: nil, tcp: tcpOptions)
        params.acceptLocalOnly = false
        params.allowLocalEndpointReuse = true

        let listener = try NWListener(using: params, on: port)
        self.listener = listener

        listener.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            switch newState {
            case .ready:
                Log.info("video", "Listening on port \(self.port)")
                self.state = .listening
            case .failed(let err):
                Log.error("video", "Listener failed: \(err)")
                self.state = .failed(err.localizedDescription)
            case .cancelled:
                self.state = .stopped
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] incoming in
            self?.handleIncoming(incoming)
        }

        listener.start(queue: workQueue)
    }

    public func stop() {
        activeConnection?.cancel()
        activeConnection = nil
        listener?.cancel()
        listener = nil
        headerSent = false
        state = .stopped
    }

    /// Streams a single NAL unit to the active Windows client (if any). The
    /// header is sent lazily on the first NAL of a fresh connection.
    ///
    /// Includes lightweight backpressure: if the socket has more than
    /// `pendingSendHighWaterMark` bytes outstanding we drop *non-parameter*
    /// NAL units rather than queueing more frames. Parameter sets (SPS/PPS/
    /// VPS) and keyframes are always sent so the decoder can recover.
    public func send(nal: Data, header: VideoStreamHeader, isParameterSet: Bool = false, isKeyframe: Bool = false) {
        guard let conn = activeConnection else {
            // No subscriber yet — drop frame. The Windows client will join
            // soon, ACTIVATE us, and trigger a keyframe.
            return
        }

        pendingSendLock.lock()
        let outstanding = pendingSendBytes
        pendingSendLock.unlock()

        if outstanding > Self.pendingSendHighWaterMark, !(isParameterSet || isKeyframe) {
            Log.warning("video", "Dropping NAL (\(nal.count) bytes) — \(outstanding) bytes already in-flight")
            return
        }

        var payload = Data()
        if !headerSent {
            payload.append(header.encode())
            headerSent = true
            Log.info("video", "Sent video stream header (\(header.codec) \(header.width)x\(header.height)@\(header.fps))")
        }
        payload.append(NALFraming.frame(nal))

        let size = payload.count
        pendingSendLock.lock()
        pendingSendBytes += size
        pendingSendLock.unlock()

        conn.send(content: payload, completion: .contentProcessed { [weak self] error in
            self?.pendingSendLock.lock()
            self?.pendingSendBytes -= size
            self?.pendingSendLock.unlock()
            if let error {
                Log.error("video", "Send error: \(error.localizedDescription)")
            }
        })
    }

    // MARK: - Internal

    private func handleIncoming(_ connection: NWConnection) {
        if activeConnection != nil {
            Log.warning("video", "Rejecting concurrent connection from \(connection.endpoint)")
            connection.cancel()
            return
        }
        activeConnection = connection
        headerSent = false

        connection.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            switch newState {
            case .ready:
                Log.info("video", "Windows client connected from \(connection.endpoint)")
                self.state = .streaming
            case .failed(let err):
                Log.error("video", "Connection failed: \(err.localizedDescription)")
                self.tearDown()
            case .cancelled:
                Log.info("video", "Connection cancelled")
                self.tearDown()
            default:
                break
            }
        }

        connection.start(queue: workQueue)
    }

    private func tearDown() {
        activeConnection = nil
        headerSent = false
        if listener != nil {
            state = .listening
        } else {
            state = .stopped
        }
    }

    /// True when there's a live Windows client. The encoder uses this to
    /// avoid wasted work if nobody is listening.
    public var hasSubscriber: Bool { activeConnection != nil }
}
