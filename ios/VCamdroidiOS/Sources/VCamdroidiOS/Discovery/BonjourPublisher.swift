import Foundation
import Network
import UIKit

/// Advertises the iOS device on the local network so the Windows client can
/// discover it without QR codes or typing IP addresses. Publishes the
/// service type `_vcamdroid._tcp.` on the control port (6969).
///
/// TXT records carry enough metadata for Windows to short-circuit the
/// descriptor handshake when listing devices.
public final class BonjourPublisher {
    public enum State: Equatable {
        case stopped
        case advertising
        case failed(String)
    }

    public var stateHandler: ((State) -> Void)?

    public private(set) var state: State = .stopped {
        didSet {
            guard oldValue != state else { return }
            let snapshot = state
            DispatchQueue.main.async { [stateHandler] in stateHandler?(snapshot) }
        }
    }

    private let serviceType: String
    private let controlPort: NWEndpoint.Port
    private let videoPort: UInt16
    private let queue = DispatchQueue(label: "vcamdroid.bonjour", qos: .utility)
    private var listener: NWListener?

    public init(
        controlPort: UInt16 = 6969,
        videoPort: UInt16 = 8554,
        serviceType: String = "_vcamdroid._tcp."
    ) {
        self.controlPort = NWEndpoint.Port(rawValue: controlPort) ?? 6969
        self.videoPort = videoPort
        self.serviceType = serviceType
    }

    public var isPublishing: Bool {
        if case .advertising = state { return true }
        return listener != nil
    }

    public func start(deviceName: String) {
        stop()

        // We piggy-back on a passive NWListener purely for the Bonjour
        // advertisement. The listener is bound but isn't expected to accept
        // connections — actual control traffic flows in the opposite direction
        // (iOS dials Windows on 6969). Having the listener present is what
        // gives us a free, robust advertisement.
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        do {
            let listener = try NWListener(using: params, on: controlPort)
            let txtDict: [String: Data] = [
                "dev":     Data("ios".utf8),
                "name":    Data(deviceName.utf8),
                "version": Data("2".utf8),
                "ctl":     Data(String(controlPort.rawValue).utf8),
                "vid":     Data(String(videoPort).utf8)
            ]
            let txtData = NetService.data(fromTXTRecord: txtDict)
            listener.service = NWListener.Service(
                name: deviceName,
                type: serviceType,
                txtRecord: txtData
            )
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    Log.info("bonjour", "Advertising \(self.serviceType) for \(deviceName)")
                    self.state = .advertising
                case .failed(let err):
                    Log.error("bonjour", "Failed: \(err.localizedDescription)")
                    self.state = .failed(err.localizedDescription)
                case .cancelled:
                    self.state = .stopped
                default: break
                }
            }
            listener.newConnectionHandler = { connection in
                // We don't accept Bonjour-discovered control connections —
                // iOS dials out instead — so reject cleanly.
                connection.cancel()
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            Log.error("bonjour", "Listener init failed: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        state = .stopped
    }
}
