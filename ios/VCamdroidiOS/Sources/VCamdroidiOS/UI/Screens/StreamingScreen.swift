import SwiftUI

/// Live streaming screen. Shows the camera preview behind a translucent
/// status overlay with real-time metrics and a disconnect action. When
/// "studio mode" is engaged from the Windows UI, the screen dims to deep
/// black with a single status pulse — designed for use on a phone clamped
/// to a tripod where any extra light would bleed into the scene.
public struct StreamingScreen: View {
    @ObservedObject var controller: StreamController
    @State private var lastDimWhenStudioMode: CGFloat = UIScreen.main.brightness

    public init(controller: StreamController) {
        self.controller = controller
    }

    public var body: some View {
        ZStack(alignment: .top) {
            if controller.studioModeEnabled {
                studioBackground
            } else {
                CameraPreviewView(session: controller.captureSession)
                    .ignoresSafeArea()
            }

            VStack {
                statusOverlay
                Spacer()
                bottomBar
            }
            .padding(Theme.Spacing.md)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            lastDimWhenStudioMode = UIScreen.main.brightness
        }
        .onChange(of: controller.studioModeEnabled) { newValue in
            applyBrightness(forStudio: newValue)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            applyBrightness(forStudio: false)
        }
    }

    @ViewBuilder
    private var studioBackground: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: Theme.Spacing.lg) {
                Spacer()
                Circle()
                    .fill(Theme.Color.success)
                    .frame(width: 12, height: 12)
                    .modifier(StudioPulseModifier())
                Text("Studio mode")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .textCase(.uppercase)
                    .kerning(2)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                streamingPill
                HStack(spacing: Theme.Spacing.xs) {
                    MetricBadge(label: "FPS", value: String(format: "%.0f", controller.lastMetrics.fps))
                    MetricBadge(label: "Mbps", value: String(format: "%.1f", controller.lastMetrics.bitrateKbps / 1_000))
                    MetricBadge(label: "Res", value: "\(controller.configuration.width)×\(controller.configuration.height)")
                    if controller.microphoneEnabled {
                        MetricBadge(label: "Mic", value: "On")
                    }
                }
            }
            Spacer()
        }
        .opacity(controller.studioModeEnabled ? 0.0 : 1.0)
    }

    @ViewBuilder
    private var streamingPill: some View {
        switch controller.videoState {
        case .streaming:
            StatusPill("Streaming", icon: "wave.3.right", tone: .success)
        case .listening:
            StatusPill("Waiting for PC", icon: "antenna.radiowaves.left.and.right", tone: .accent)
        case .idle:
            StatusPill("Idle", icon: "pause.circle", tone: .neutral)
        case .failed(let reason):
            StatusPill(reason, icon: "exclamationmark.triangle.fill", tone: .danger)
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        HStack {
            Spacer()
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                controller.disconnect()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(Theme.Spacing.md)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            Spacer()
        }
        .opacity(controller.studioModeEnabled ? 0.0 : 1.0)
    }

    private func applyBrightness(forStudio: Bool) {
        if forStudio {
            lastDimWhenStudioMode = UIScreen.main.brightness
            UIScreen.main.brightness = 0.05
        } else {
            UIScreen.main.brightness = lastDimWhenStudioMode
        }
    }
}

/// Slow, polite pulse used as the heartbeat indicator while in studio mode.
private struct StudioPulseModifier: ViewModifier {
    @State private var pulse = false

    func body(content: Content) -> some View {
        content
            .opacity(pulse ? 0.35 : 1.0)
            .scaleEffect(pulse ? 0.85 : 1.0)
            .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}
