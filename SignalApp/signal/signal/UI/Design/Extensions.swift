import SwiftUI

// MARK: - Color from hex string
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Date formatting
extension Date {
    var relativeDisplay: String {
        let diff = Date().timeIntervalSince(self)
        switch diff {
        case ..<60:           return "just now"
        case ..<3600:         return "\(Int(diff / 60))m ago"
        case ..<86400:        return "\(Int(diff / 3600))h ago"
        case ..<604800:       return "\(Int(diff / 86400))d ago"
        default:
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            return f.string(from: self)
        }
    }

    var shortDateTime: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d · h:mma"
        return f.string(from: self).lowercased()
    }
}

// MARK: - Category display names
extension String {
    var categoryDisplayName: String {
        switch self {
        case "model_release":   return "MODEL"
        case "benchmark":       return "BENCHMARK"
        case "research_paper":  return "RESEARCH"
        case "open_source":     return "OPEN SOURCE"
        case "engineering_post": return "ENGINEERING"
        case "funding":         return "FUNDING"
        case "industry":        return "INDUSTRY"
        case "noise":           return "NOISE"
        default:                return self.uppercased()
        }
    }
}

// MARK: - View modifiers
extension View {
    func cardStyle() -> some View {
        self
            .background(DesignSystem.Colors.surface)
            .overlay(
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(DesignSystem.Colors.border),
                alignment: .bottom
            )
    }

    func signalBackground() -> some View {
        self.background(DesignSystem.Colors.background)
    }
}
