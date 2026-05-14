import Foundation

/// Rolling 1-second metrics window for the UI / Windows status line.
public final class StreamMetrics {
    public struct Snapshot: Equatable {
        public let fps: Double
        public let bitrateKbps: Double
        public let droppedFrames: Int
    }

    public var snapshotHandler: ((Snapshot) -> Void)?

    private let lock = NSLock()
    private var frameCount = 0
    private var byteCount = 0
    private var droppedCount = 0
    private var windowStart = CFAbsoluteTimeGetCurrent()
    private var timer: DispatchSourceTimer?
    private let callbackQueue: DispatchQueue

    public init(callbackQueue: DispatchQueue = .main) {
        self.callbackQueue = callbackQueue
    }

    public func start() {
        stop()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 1, repeating: 1.0)
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer
        timer.resume()
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        lock.lock()
        frameCount = 0
        byteCount = 0
        droppedCount = 0
        windowStart = CFAbsoluteTimeGetCurrent()
        lock.unlock()
    }

    public func recordFrame(byteSize: Int) {
        lock.lock()
        frameCount += 1
        byteCount += byteSize
        lock.unlock()
    }

    public func recordDrop() {
        lock.lock()
        droppedCount += 1
        lock.unlock()
    }

    private func tick() {
        lock.lock()
        let frames = frameCount
        let bytes = byteCount
        let drops = droppedCount
        let elapsed = max(0.001, CFAbsoluteTimeGetCurrent() - windowStart)
        frameCount = 0
        byteCount = 0
        droppedCount = 0
        windowStart = CFAbsoluteTimeGetCurrent()
        lock.unlock()

        let snapshot = Snapshot(
            fps: Double(frames) / elapsed,
            bitrateKbps: Double(bytes * 8) / 1_000.0 / elapsed,
            droppedFrames: drops
        )
        let handler = snapshotHandler
        callbackQueue.async { handler?(snapshot) }
    }
}
