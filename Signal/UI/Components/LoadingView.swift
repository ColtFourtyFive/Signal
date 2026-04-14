import SwiftUI

struct LoadingView: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(DesignSystem.Colors.textTertiary)
            Text("Loading...")
                .font(DesignSystem.Typography.mono)
                .foregroundColor(DesignSystem.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.xl)
    }
}

struct FullScreenLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(DesignSystem.Colors.textSecondary)
                .scaleEffect(1.2)
            Text("SIGNAL")
                .font(DesignSystem.Typography.label)
                .foregroundColor(DesignSystem.Colors.textTertiary)
                .kerning(4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .signalBackground()
    }
}
