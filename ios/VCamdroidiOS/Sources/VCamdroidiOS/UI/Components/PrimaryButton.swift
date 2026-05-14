import SwiftUI

/// Sleek primary action button used throughout the connection flow. Uses
/// the platform haptic feedback so each tap feels intentional.
public struct PrimaryButton: View {
    private let title: String
    private let icon: String?
    private let action: () -> Void
    private let isLoading: Bool

    @Environment(\.isEnabled) private var isEnabled

    public init(_ title: String, icon: String? = nil, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        }) {
            HStack(spacing: Theme.Spacing.xs) {
                if isLoading {
                    ProgressView()
                        .tint(Theme.Color.textPrimary)
                } else if let icon {
                    Image(systemName: icon)
                }
                Text(title)
            }
            .font(Theme.Font.headline)
            .foregroundStyle(Theme.Color.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
            .background(
                LinearGradient(
                    colors: [Theme.Color.accent, Theme.Color.accent.opacity(0.75)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .opacity(isEnabled ? 1.0 : 0.45)
        }
        .disabled(isLoading)
    }
}
