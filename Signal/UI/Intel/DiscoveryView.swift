import SwiftUI

struct DiscoveryView: View {
    @Bindable var viewModel: IntelViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            sectionHeader("DISCOVERY")

            // Summary stat
            HStack {
                Image(systemName: "sparkle")
                    .foregroundColor(DesignSystem.Colors.accent)
                Text("Signal found \(viewModel.feeds.filter(\.isAutoDiscovered).count) sources autonomously")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            .padding(DesignSystem.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignSystem.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Pending sources
            if !viewModel.pendingDiscovered.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("AWAITING REVIEW")
                        .font(DesignSystem.Typography.label)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                        .kerning(1)

                    ForEach(viewModel.pendingDiscovered) { source in
                        discoveredSourceRow(source)
                    }
                }
            } else {
                Text("No pending sources")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(DesignSystem.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func discoveredSourceRow(_ source: DiscoveredSource) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(source.name ?? source.url ?? "Unknown")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    if let reason = source.discoveryReason {
                        Text(reason)
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                if let score = source.avgScore {
                    Text(String(format: "%.1f", score))
                        .font(DesignSystem.Typography.monoLarge)
                        .foregroundColor(DesignSystem.Colors.score(score))
                }
            }

            HStack(spacing: 8) {
                Button {
                    HapticService.notification(.success)
                    viewModel.approveSource(source)
                } label: {
                    Label("Add", systemImage: "checkmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(DesignSystem.Colors.accent)
                        .clipShape(Capsule())
                }

                Button {
                    HapticService.impact(.light)
                    viewModel.rejectSource(source)
                } label: {
                    Label("Skip", systemImage: "xmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(DesignSystem.Colors.surfaceElevated)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
        )
    }
}

private func sectionHeader(_ title: String) -> some View {
    Text(title)
        .font(DesignSystem.Typography.label)
        .foregroundColor(DesignSystem.Colors.textTertiary)
        .kerning(2)
}
