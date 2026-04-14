import SwiftUI

struct FilterPillsView: View {
    @Binding var selected: String?

    private let categories: [(id: String?, label: String)] = [
        (nil,                "All"),
        ("model_release",    "Models"),
        ("research_paper",   "Research"),
        ("benchmark",        "Benchmarks"),
        ("open_source",      "Open Source"),
        ("engineering_post", "Engineering"),
        ("funding",          "Funding"),
        ("industry",         "Industry"),
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.label) { item in
                    Button {
                        withAnimation(DesignSystem.Animation.spring) {
                            selected = item.id
                        }
                        HapticService.selection()
                    } label: {
                        Text(item.label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(
                                selected == item.id
                                    ? .white
                                    : DesignSystem.Colors.textSecondary
                            )
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                selected == item.id
                                    ? DesignSystem.Colors.accent
                                    : DesignSystem.Colors.surfaceElevated
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .animation(DesignSystem.Animation.spring, value: selected)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.sm)
        }
    }
}
