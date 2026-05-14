import SwiftUI

/// Centralized design tokens. Keeping these in one place lets us A/B the
/// visual identity without touching every screen and makes "premium feel"
/// a one-line change.
public enum Theme {
    public enum Color {
        public static let background = SwiftUI.Color(red: 0.05, green: 0.05, blue: 0.06)
        public static let surface     = SwiftUI.Color(red: 0.10, green: 0.10, blue: 0.12)
        public static let surfaceElevated = SwiftUI.Color(red: 0.13, green: 0.13, blue: 0.15)
        public static let accent      = SwiftUI.Color(red: 0.31, green: 0.78, blue: 1.00)  // electric blue
        public static let success     = SwiftUI.Color(red: 0.36, green: 0.85, blue: 0.55)
        public static let warning     = SwiftUI.Color(red: 1.00, green: 0.72, blue: 0.32)
        public static let danger      = SwiftUI.Color(red: 1.00, green: 0.38, blue: 0.40)
        public static let textPrimary   = SwiftUI.Color.white
        public static let textSecondary = SwiftUI.Color(white: 1.0, opacity: 0.65)
        public static let textTertiary  = SwiftUI.Color(white: 1.0, opacity: 0.40)
        public static let divider     = SwiftUI.Color(white: 1.0, opacity: 0.08)
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
        public static let titleLarge   = SwiftUI.Font.system(size: 32, weight: .bold, design: .rounded)
        public static let title        = SwiftUI.Font.system(size: 22, weight: .semibold, design: .rounded)
        public static let headline     = SwiftUI.Font.system(size: 17, weight: .semibold)
        public static let body         = SwiftUI.Font.system(size: 15, weight: .regular)
        public static let caption      = SwiftUI.Font.system(size: 13, weight: .medium, design: .rounded)
        public static let mono         = SwiftUI.Font.system(size: 13, weight: .medium, design: .monospaced)
    }
}
