import SwiftUI

/// Connection screen — host/port entry and connect button. In Phase 3 a
/// Bonjour-driven device list replaces the manual entry path.
public struct ConnectionScreen: View {
    @ObservedObject var controller: StreamController
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
                hostField
                portField
                Spacer()
                statusBar
                connectButton
            }
            .padding(Theme.Spacing.lg)
        }
        .preferredColorScheme(.dark)
    }

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

    @ViewBuilder
    private var statusBar: some View {
        HStack(spacing: Theme.Spacing.xs) {
            switch controller.connectionState {
            case .disconnected:
                StatusPill("Idle", icon: "circle", tone: .neutral)
            case .connecting:
                StatusPill("Connecting…", icon: "antenna.radiowaves.left.and.right", tone: .warning)
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
    }

    private var connectButtonTitle: String {
        switch controller.connectionState {
        case .connected: return "Disconnect"
        case .connecting: return "Connecting…"
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
}
