import SwiftUI

struct CategoryPillView: View {
    let category: String
    var small: Bool = true

    var body: some View {
        Text(category.categoryDisplayName)
            .font(small ? DesignSystem.Typography.label : DesignSystem.Typography.mono)
            .foregroundColor(DesignSystem.Colors.textSecondary)
            .padding(.horizontal, small ? 6 : 8)
            .padding(.vertical, small ? 2 : 4)
            .background(DesignSystem.Colors.surfaceElevated)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
