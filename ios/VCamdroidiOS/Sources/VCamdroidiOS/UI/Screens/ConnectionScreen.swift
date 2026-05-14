import SwiftUI

/// Connection screen with two modes:
///   1. **Auto** — Bonjour is advertising; waits for Windows to discover and connect.
///   2. **Manual** — User enters the Windows host IP and connects directly.
///
/// The auto path is the default since Windows now runs an mDNS browser that
/// auto-discovers iPhones on the LAN. The manual path remains available as a
/// fallback for networks where mDNS is blocked (corporate firewalls, etc).
public struct ConnectionScreen: View {
    @ObservedObject var controller: StreamController
    @State private var mode: Mode = .auto
    @State private var host: String = "192.168.1.10"
    @State private var port: String = "6969"
    @FocusState private var focused: Field?

    public init(controller: StreamController) {
        self.controller = controller
    }

    public var body: some View {
        ZStack {
            Theme.Color.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                Spacer().frame(height: Theme.Spacing.md)
                modePicker
                Spacer().frame(height: Theme.Spacing.xs)

                switch mode {
                case .auto:
                    autoDiscoveryView
                case .manual:
                    hostField
                    portField
                }

                Spacer()
                statusBar
                connectButton
            }
            .padding(Theme.Spacing.lg)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("VCamdroid")
                .font(Theme.Font.titleLarge)
                .foregroundStyle(Theme.Color.textPrimary)
            Text("Use your iPhone as a Windows webcam")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }

    // MARK: - Mode picker

    @ViewBuilder
    private var modePicker: some View {
        HStack(spacing: 0) {
            modeTab("Auto", systemImage: "antenna.radiowaves.left.and.right", isSelected: mode == .auto) {
                withAnimation(.easeInOut(duration: 0.2)) { mode = .auto }
            }
            modeTab("Manual", systemImage: "keyboard", isSelected: mode == .manual) {
                withAnimation(.easeInOut(duration: 0.2)) { mode = .manual }
            }
        }
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func modeTab(_ title: String, systemImage: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xxs) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(Theme.Font.caption)
            }
            .foregroundStyle(isSelected ? Theme.Color.textPrimary : Theme.Color.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.sm)
            .background(isSelected ? Theme.Color.surfaceElevated : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(2)
    }

    // MARK: - Auto discovery view

    @ViewBuilder
    private var autoDiscoveryView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            VStack(spacing: Theme.Spacing.md) {
                ZStack {
                    // Pulsing rings
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .stroke(Theme.Color.accent.opacity(0.15), lineWidth: 1.5)
                            .frame(width: CGFloat(80 + i * 40), height: CGFloat(80 + i * 40))
                            .scaleEffect(controller.connectionState == .connecting ? 1.15 : 1.0)
                            .opacity(controller.connectionState == .connecting ? 0.0 : 1.0)
                            .animation(
                                .easeInOut(duration: 2.0)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.4),
                                value: controller.connectionState
                            )
                    }

                    Image(systemName: "iphone.radiowaves.left.and.right")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(Theme.Color.accent)
                }

                Text("Waiting for VCamdroid Desktop")
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.Color.textPrimary)

                Text("Make sure your PC and iPhone are on the same\nWi-Fi network, or connected via USB cable.")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
    }

    // MARK: - Manual fields

    @ViewBuilder
    private var hostField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text("Windows host")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)
            TextField("", text: $host, prompt: Text("192.168.1.10").foregroundColor(Theme.Color.textTertiary))
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.textPrimary)
                .keyboardType(.numbersAndPunctuation)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focused, equals: .host)
                .padding(.vertical, Theme.Spacing.sm)
                .padding(.horizontal, Theme.Spacing.md)
                .background(Theme.Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @ViewBuilder
    private var portField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text("Control port")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)
            TextField("", text: $port, prompt: Text("6969").foregroundColor(Theme.Color.textTertiary))
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.textPrimary)
                .keyboardType(.numberPad)
                .focused($focused, equals: .port)
                .padding(.vertical, Theme.Spacing.sm)
                .padding(.horizontal, Theme.Spacing.md)
                .background(Theme.Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Status & action

    @ViewBuilder
    private var statusBar: some View {
        HStack(spacing: Theme.Spacing.xs) {
            switch controller.connectionState {
            case .disconnected:
                if mode == .auto {
                    StatusPill("Broadcasting", icon: "antenna.radiowaves.left.and.right", tone: .accent)
                } else {
                    StatusPill("Idle", icon: "circle", tone: .neutral)
                }
            case .connecting:
                StatusPill("Connecting...", icon: "antenna.radiowaves.left.and.right", tone: .warning)
            case .connected(let host, let port):
                StatusPill("\(host):\(port)", icon: "checkmark.circle.fill", tone: .success)
            case .failed(let reason):
                StatusPill(reason, icon: "exclamationmark.triangle.fill", tone: .danger)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var connectButton: some View {
        if mode == .manual {
            PrimaryButton(
                connectButtonTitle,
                icon: connectButtonIcon,
                isLoading: controller.connectionState == .connecting
            ) {
                focused = nil
                switch controller.connectionState {
                case .connected:
                    controller.disconnect()
                default:
                    Task {
                        await controller.connect(host: host, controlPort: UInt16(port) ?? 6969)
                    }
                }
            }
        } else {
            // In auto mode, show a subtle disconnect button if connected,
            // otherwise the waiting animation conveys the state.
            if case .connected = controller.connectionState {
                PrimaryButton("Disconnect", icon: "xmark") {
                    controller.disconnect()
                }
            }
        }
    }

    private var connectButtonTitle: String {
        switch controller.connectionState {
        case .connected: return "Disconnect"
        case .connecting: return "Connecting..."
        default: return "Connect"
        }
    }

    private var connectButtonIcon: String? {
        switch controller.connectionState {
        case .connected: return "xmark"
        case .connecting: return nil
        default: return "play.fill"
        }
    }

    private enum Field { case host, port }
    private enum Mode { case auto, manual }
}
