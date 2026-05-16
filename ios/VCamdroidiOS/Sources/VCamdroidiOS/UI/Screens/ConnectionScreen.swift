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
    @State private var host: String = RecentHostsStore.load().first ?? "192.168.1.10"
    @State private var port: String = "6969"
    @State private var recentHosts: [String] = RecentHostsStore.load()
    @FocusState private var focused: Field?

    public init(controller: StreamController) {
        self.controller = controller
    }

    public var body: some View {
        ZStack {
            Theme.Color.background.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header
                    gentleStepsCard
                    modePicker

                    switch mode {
                    case .auto:
                        autoDiscoveryView
                    case .manual:
                        manualFieldsCard
                    }

                    statusBar
                    connectButton
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            recentHosts = RecentHostsStore.load()
            if mode == .auto {
                controller.startAutoDiscovery()
            }
        }
        .onDisappear {
            if mode == .auto, case .disconnected = controller.connectionState {
                controller.stopAutoDiscovery()
            }
        }
        .onChange(of: mode) { newMode in
            if newMode == .auto {
                controller.startAutoDiscovery()
            } else {
                controller.stopAutoDiscovery()
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("VCamdroid")
                .font(Theme.Font.titleLarge)
                .foregroundStyle(Theme.Color.textPrimary)
            Text("Turn your iPhone into a gentle, reliable webcam for your PC.")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Short, low-friction orientation for people who skimp instructions.
    @ViewBuilder
    private var gentleStepsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("How it works")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)
            stepRow(number: "1", text: "Open VCamdroid on your Windows PC and leave it running.")
            stepRow(number: "2", text: "Come back here — stay on this screen while connecting.")
            stepRow(number: "3", text: "On the PC, choose your iPhone from the camera list.")
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(Theme.Color.cardStroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func stepRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Text(number)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Color.accent)
                .frame(width: 22, height: 22)
                .background(Theme.Color.accent.opacity(0.14))
                .clipShape(Circle())
            Text(text)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.textPrimary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Mode picker

    @ViewBuilder
    private var modePicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Connection style")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)
            HStack(spacing: 0) {
                modeTab(title: "Easy", subtitle: "Wi‑Fi or USB", systemImage: "sparkles", isSelected: mode == .auto) {
                    withAnimation(.easeInOut(duration: 0.22)) { mode = .auto }
                }
                modeTab(title: "Custom", subtitle: "Type PC address", systemImage: "keyboard", isSelected: mode == .manual) {
                    withAnimation(.easeInOut(duration: 0.22)) { mode = .manual }
                }
            }
            .background(Theme.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.Color.cardStroke, lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func modeTab(title: String, subtitle: String, systemImage: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.xxs) {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .medium))
                    Text(title)
                        .font(Theme.Font.caption)
                }
                Text(subtitle)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            .foregroundStyle(isSelected ? Theme.Color.textPrimary : Theme.Color.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Theme.Spacing.sm)
            .padding(.horizontal, Theme.Spacing.md)
            .background(isSelected ? Theme.Color.surfaceElevated : SwiftUI.Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(3)
    }

    // MARK: - Auto discovery view

    @ViewBuilder
    private var autoDiscoveryView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            VStack(spacing: Theme.Spacing.md) {
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .stroke(Theme.Color.accent.opacity(0.12), lineWidth: 1.5)
                            .frame(width: CGFloat(80 + i * 40), height: CGFloat(80 + i * 40))
                            .scaleEffect(controller.connectionState == .connecting ? 1.12 : 1.0)
                            .opacity(controller.connectionState == .connecting ? 0.0 : 1.0)
                            .animation(
                                .easeInOut(duration: 2.2)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(i) * 0.45),
                                value: controller.connectionState
                            )
                    }

                    Image(systemName: "iphone.radiowaves.left.and.right")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(Theme.Color.accent.opacity(0.95))
                }

                Text("Ready when you are")
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.Color.textPrimary)

                Text("Your PC can find this phone over Wi‑Fi.\nWith a cable, tap below — your PC finishes the rest.")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                PrimaryButton("Use USB cable", icon: "cable.connector") {
                    Task { await controller.connectUsb() }
                }
                .padding(.top, Theme.Spacing.xs)
            }
            .padding(.vertical, Theme.Spacing.md)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var manualFieldsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("If your network hides automatic discovery, enter what your PC shows under Connect → address.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            hostField
            portField
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(Theme.Color.cardStroke, lineWidth: 1)
        )
    }

    // MARK: - Manual fields

    @ViewBuilder
    private var hostField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text("Windows PC address")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)
            if !recentHosts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(recentHosts, id: \.self) { entry in
                            Button(entry) { host = entry }
                                .font(Theme.Font.caption)
                                .padding(.horizontal, Theme.Spacing.sm)
                                .padding(.vertical, Theme.Spacing.xxs)
                                .background(Theme.Color.surfaceElevated)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
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
            Text("Port (usually leave as-is)")
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
                    StatusPill("Sharing quietly…", icon: "leaf", tone: .accent)
                } else {
                    StatusPill("Not connected", icon: "moon.zzz", tone: .neutral)
                }
            case .connecting:
                StatusPill("Connecting gently…", icon: "antenna.radiowaves.left.and.right", tone: .warning)
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
                        RecentHostsStore.remember(host)
                        recentHosts = RecentHostsStore.load()
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
        case .connecting: return "Connecting…"
        default: return "Connect to PC"
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
