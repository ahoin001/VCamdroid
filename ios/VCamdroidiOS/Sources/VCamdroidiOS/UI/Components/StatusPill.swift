import SwiftUI

/// Reusable rounded status indicator. Used in both the connection screen
/// and the live overlay during streaming.
public struct StatusPill: View {
    public enum Tone { case neutral, success, warning, danger, accent }

    private let label: String
    private let icon: String?
    private let tone: Tone

    public init(_ label: String, icon: String? = nil, tone: Tone = .neutral) {
        self.label = label
        self.icon = icon
        self.tone = tone
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if let icon { Image(systemName: icon) }
            Text(label)
        }
        .font(Theme.Font.caption)
        .foregroundStyle(foreground)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xxs)
        .background(background)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(border, lineWidth: 0.5)
        )
    }

    private var foreground: Color {
        switch tone {
        case .neutral: return Theme.Color.textSecondary
        case .success: return Theme.Color.success
        case .warning: return Theme.Color.warning
        case .danger:  return Theme.Color.danger
        case .accent:  return Theme.Color.accent
        }
    }

    private var background: Color {
        switch tone {
        case .neutral: return Theme.Color.surface
        case .success: return Theme.Color.success.opacity(0.12)
        case .warning: return Theme.Color.warning.opacity(0.12)
        case .danger:  return Theme.Color.danger.opacity(0.12)
        case .accent:  return Theme.Color.accent.opacity(0.12)
        }
    }

    private var border: Color {
        switch tone {
        case .neutral: return Theme.Color.divider
        case .success: return Theme.Color.success.opacity(0.35)
        case .warning: return Theme.Color.warning.opacity(0.35)
        case .danger:  return Theme.Color.danger.opacity(0.35)
        case .accent:  return Theme.Color.accent.opacity(0.35)
        }
    }
}
