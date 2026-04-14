import SwiftUI

struct EntityPillsView: View {
    let entities: [String]

    var body: some View {
        if !entities.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(entities, id: \.self) { entity in
                        Text(entity)
                            .font(DesignSystem.Typography.mono)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .overlay(
                                Capsule()
                                    .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
                            )
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
            }
        }
    }
}
