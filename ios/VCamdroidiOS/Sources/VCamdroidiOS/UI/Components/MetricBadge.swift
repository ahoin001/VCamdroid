import SwiftUI

/// Small "key/value" badge used in the streaming overlay.
public struct MetricBadge: View {
    private let label: String
    private let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Color.textTertiary)
                .textCase(.uppercase)
                .kerning(0.6)
            Text(value)
                .font(Theme.Font.mono)
                .foregroundStyle(Theme.Color.textPrimary)
                .monospacedDigit()
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Color.surface.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
