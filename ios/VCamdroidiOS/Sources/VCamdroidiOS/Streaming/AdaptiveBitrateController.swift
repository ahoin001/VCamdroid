import Foundation

/// Lightweight ABR controller. Watches `StreamMetrics` snapshots and nudges
/// the encoder bitrate up when there's headroom, down when the actual fps
/// drops below the target — a strong proxy for network or encoder distress.
///
/// We deliberately keep the policy simple and observable: production
/// improvements (RTT-aware, bandwidth probing) can swap the policy without
/// touching the controller's surface.
public final class AdaptiveBitrateController {
    public enum Policy {
        case staticBitrate(kbps: Int)
        case adaptive(minKbps: Int, maxKbps: Int)
    }

    private weak var encoder: VideoEncoder?
    private var policy: Policy
    private var currentKbps: Int
    private var targetFps: Int
    private var lastAdjustAt: CFAbsoluteTime = 0

    public init(encoder: VideoEncoder, policy: Policy, targetFps: Int) {
        self.encoder = encoder
        self.policy = policy
        self.targetFps = targetFps
        switch policy {
        case .staticBitrate(let kbps): self.currentKbps = kbps
        case .adaptive(_, let maxKbps): self.currentKbps = maxKbps
        }
    }

    public func updatePolicy(_ policy: Policy, targetFps: Int) {
        self.policy = policy
        self.targetFps = targetFps
        switch policy {
        case .staticBitrate(let kbps):
            currentKbps = kbps
            encoder?.updateBitrate(kbps)
        case .adaptive(_, let maxKbps):
            currentKbps = maxKbps
            encoder?.updateBitrate(maxKbps)
        }
    }

    /// Called for every metrics snapshot. Returns the bitrate currently in
    /// effect (caller may surface this in the UI).
    @discardableResult
    public func consume(snapshot: StreamMetrics.Snapshot) -> Int {
        guard case let .adaptive(minKbps, maxKbps) = policy else { return currentKbps }

        // 2-second cooldown so the rate controller stabilizes between nudges.
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastAdjustAt > 2.0 else { return currentKbps }

        let target = Double(targetFps)
        let actual = snapshot.fps

        let lowWatermark = target * 0.85
        let highWatermark = target * 0.98

        if actual < lowWatermark {
            currentKbps = max(minKbps, Int(Double(currentKbps) * 0.8))
            encoder?.updateBitrate(currentKbps)
            Log.info("abr", "Dropped to \(currentKbps) kbps (fps=\(actual))")
            lastAdjustAt = now
        } else if actual >= highWatermark && currentKbps < maxKbps {
            currentKbps = min(maxKbps, Int(Double(currentKbps) * 1.1))
            encoder?.updateBitrate(currentKbps)
            Log.info("abr", "Bumped to \(currentKbps) kbps (fps=\(actual))")
            lastAdjustAt = now
        }

        return currentKbps
    }
}
