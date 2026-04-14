import SwiftUI

enum DesignSystem {

    // MARK: - Colors
    enum Colors {
        static let background      = Color(hex: "#080808")
        static let surface         = Color(hex: "#111111")
        static let surfaceElevated = Color(hex: "#1A1A1A")
        static let border          = Color(hex: "#222222")
        static let textPrimary     = Color(hex: "#F2F2F2")
        static let textSecondary   = Color(hex: "#888888")
        static let textTertiary    = Color(hex: "#444444")
        static let critical        = Color(hex: "#FF3B30")   // score 9-10
        static let high            = Color(hex: "#FF9F0A")   // score 7-8
        static let accent          = Color(hex: "#0A84FF")   // interactive

        static func score(_ value: Double) -> Color {
            switch value {
            case 9...10: return critical
            case 8..<9:  return high
            default:     return accent
            }
        }
    }

    // MARK: - Typography
    enum Typography {
        static let headline  = Font.system(size: 17, weight: .semibold)
        static let body      = Font.system(size: 15, weight: .regular)
        static let caption   = Font.system(size: 12, weight: .regular)
        static let mono      = Font.system(size: 11, weight: .medium, design: .monospaced)
        static let monoLarge = Font.system(size: 13, weight: .medium, design: .monospaced)
        static let label     = Font.system(size: 10, weight: .semibold, design: .monospaced)
    }

    // MARK: - Spacing
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
    }

    // MARK: - Animation
    enum Animation {
        static let spring = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.8)
        static let fast   = SwiftUI.Animation.spring(response: 0.25, dampingFraction: 0.85)
    }

    // MARK: - Score Labels
    static func scoreLabel(_ score: Double) -> String {
        switch score {
        case 9...10: return "CRITICAL"
        case 7..<9:  return "HIGH SIGNAL"
        default:     return "SIGNAL"
        }
    }
}
