import SwiftUI

/// Centralized design tokens. Keeping these in one place lets us A/B the
/// visual identity without touching every screen and makes "premium feel"
/// a one-line change.
public enum Theme {
    /// Soft night palette: calm contrast, slightly warm neutrals, muted accents.
    public enum Color {
        public static let background = SwiftUI.Color(red: 0.09, green: 0.09, blue: 0.11)
        public static let surface     = SwiftUI.Color(red: 0.13, green: 0.13, blue: 0.16)
        public static let surfaceElevated = SwiftUI.Color(red: 0.17, green: 0.17, blue: 0.21)
        public static let cardStroke = SwiftUI.Color(white: 1.0, opacity: 0.06)
        /// Gentle periwinkle — readable without feeling “tech neon”.
        public static let accent      = SwiftUI.Color(red: 0.52, green: 0.62, blue: 0.94)
        public static let success     = SwiftUI.Color(red: 0.52, green: 0.78, blue: 0.62)
        public static let warning     = SwiftUI.Color(red: 0.94, green: 0.72, blue: 0.48)
        public static let danger      = SwiftUI.Color(red: 0.92, green: 0.48, blue: 0.52)
        public static let textPrimary   = SwiftUI.Color(white: 1.0, opacity: 0.94)
        public static let textSecondary = SwiftUI.Color(white: 1.0, opacity: 0.58)
        public static let textTertiary  = SwiftUI.Color(white: 1.0, opacity: 0.38)
        public static let divider     = SwiftUI.Color(white: 1.0, opacity: 0.07)
    }

    public enum Spacing {
        public static let xxs: CGFloat = 4
        public static let xs:  CGFloat = 8
        public static let sm:  CGFloat = 12
        public static let md:  CGFloat = 16
        public static let lg:  CGFloat = 24
        public static let xl:  CGFloat = 32
    }

    public enum Radius {
        public static let card: CGFloat = 16
        public static let pill: CGFloat = 999
    }

    public enum Font {
        public static let titleLarge   = SwiftUI.Font.system(size: 30, weight: .semibold, design: .rounded)
        public static let title        = SwiftUI.Font.system(size: 21, weight: .semibold, design: .rounded)
        public static let headline     = SwiftUI.Font.system(size: 17, weight: .semibold, design: .rounded)
        public static let body         = SwiftUI.Font.system(size: 16, weight: .regular, design: .rounded)
        public static let caption      = SwiftUI.Font.system(size: 13, weight: .medium, design: .rounded)
        public static let mono         = SwiftUI.Font.system(size: 13, weight: .medium, design: .monospaced)
    }
}
