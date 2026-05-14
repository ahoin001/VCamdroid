import Foundation
import Network

/// Manages the long-lived TCP control connection to the Windows client on
/// port 6969.
///
/// Lifecycle:
/// 1. `connect(host:port:descriptor:)` opens the socket and immediately sends
///    the `DeviceDescriptor` (the only message the Windows side expects on
///    its first `read_some`).
/// 2. Incoming bytes are buffered and decoded into `ControlCommand`s via
///    `ControlPacketDecoder`. Each decoded command is delivered to the
///    `commandHandler` on the main queue so the UI / camera can react.
/// 3. The class can be reused: `disconnect()` shuts everything down cleanly
///    and `connect(...)` may be called again.
public final class ControlChannel {
    public enum State: Equatable {
        case idle
        case connecting
        case connected
        case failed(String)
    }

    /// Closure invoked for every decoded command, hopping to `callbackQueue`.
    public var commandHandler: ((ControlCommand) -> Void)?

    /// Notified on every state transition.
    public var stateHandler: ((State) -> Void)?

    public private(set) var state: State = .idle {
        didSet {
            guard oldValue != state else { return }
            let snapshot = state
            callbackQueue.async { [stateHandler] in
                stateHandler?(snapshot)
            }
        }
    }

    private let workQueue = DispatchQueue(label: "vcamdroid.control.io", qos: .userInitiated)
    private let callbackQueue: DispatchQueue
    private var connection: NWConnection?
    private var inboundBuffer = Data()

    public init(callbackQueue: DispatchQueue = .main) {
        self.callbackQueue = callbackQueue
    }

    public func connect(host: String, port: UInt16, descriptor: DeviceDescriptor) {
        disconnect()
        state = .connecting

        let endpointHost = NWEndpoint.Host(host)
        let endpointPort = NWEndpoint.Port(rawValue: port) ?? NWEndpoint.Port(integerLiteral: 6969)

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        tcpOptions.connectionTimeout = 5
        tcpOptions.enableKeepalive = true

        let params = NWParameters(tls: nil, tcp: tcpOptions)
        params.prohibitedInterfaceTypes = []

        let conn = NWConnection(host: endpointHost, port: endpointPort, using: params)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            switch newState {
            case .ready:
                Log.info("control", "Connected to \(host):\(port)")
                self.state = .connected
                self.sendDescriptor(descriptor)
                self.receiveLoop()
            case .failed(let err):
                Log.error("control", "Failed: \(err.localizedDescription)")
                self.state = .failed(err.localizedDescription)
                self.disconnect()
            case .cancelled:
                Log.info("control", "Cancelled")
                self.state = .idle
            default:
                break
            }
        }

        conn.start(queue: workQueue)
    }

    public func disconnect() {
        connection?.cancel()
        connection = nil
        inboundBuffer.removeAll(keepingCapacity: false)
    }

    /// Sends an arbitrary outbound payload (used by the error-reporting path
    /// when the phone wants to surface a failure).
    public func send(_ data: Data, completion: ((Swift.Error?) -> Void)? = nil) {
        guard let conn = connection, case .connected = state else {
            completion?(NSError(domain: "VCamdroid", code: -1, userInfo: [NSLocalizedDescriptionKey: "Control channel not connected"]))
            return
        }
        conn.send(content: data, completion: .contentProcessed { error in
            if let error {
                Log.error("control", "Send error: \(error.localizedDescription)")
            }
            completion?(error)
        })
    }

    // MARK: - Internal

    private func sendDescriptor(_ descriptor: DeviceDescriptor) {
        let payload = descriptor.encode()
        Log.debug("control", "Sending descriptor (\(payload.count) bytes)")
        send(payload)
    }

    private func receiveLoop() {
        guard let conn = connection else { return }
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4_096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.inboundBuffer.append(data)
                self.drainInboundBuffer()
            }
            if let error {
                Log.error("control", "Receive error: \(error.localizedDescription)")
                self.state = .failed(error.localizedDescription)
                self.disconnect()
                return
            }
            if isComplete {
                Log.info("control", "Remote closed connection")
                self.state = .idle
                self.disconnect()
                return
            }
            self.receiveLoop()
        }
    }

    private func drainInboundBuffer() {
        do {
            let (commands, unconsumed) = try ControlPacketDecoder.decodeAll(inboundBuffer)
            inboundBuffer = unconsumed
            for cmd in commands {
                let handler = commandHandler
                callbackQueue.async {
                    handler?(cmd)
                }
            }
        } catch {
            Log.error("control", "Decode error: \(error). Dropping buffer.")
            // Defensive: if we hit a parse error, drop the buffer so we don't
            // get stuck in a bad state. Windows can re-send any sticky config
            // on next user action.
            inboundBuffer.removeAll(keepingCapacity: false)
        }
    }
}
