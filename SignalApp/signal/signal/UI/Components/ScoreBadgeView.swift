import SwiftUI

struct ScoreBadgeView: View {
    let score: Double
    var large: Bool = false

    private var color: Color { DesignSystem.Colors.score(score) }
    private var label: String { DesignSystem.scoreLabel(score) }

    var body: some View {
        if large {
            HStack(spacing: 6) {
                Text(String(format: "%.0f", score))
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
                Text("·")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(color.opacity(0.6))
                Text(label)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(color)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            HStack(spacing: 3) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(String(format: "%.1f", score))
                    .font(DesignSystem.Typography.mono)
                    .foregroundColor(color)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}
