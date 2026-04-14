import SwiftUI
import Charts

struct TasteProfileView: View {
    let stats: Stats
    let profile: TasteProfile?
    let interactionCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            sectionHeader("TASTE PROFILE")

            if interactionCount < 5 {
                emptyStateView
            } else if profile == nil || (profile?.confidenceScore ?? 0) < 0.4 {
                learningStateView
            } else if let profile {
                profileView(profile)
            }

            // Stats row always shown
            statsRow
        }
    }

    // MARK: - Empty state (< 5 interactions)

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.circle")
                .font(.system(size: 40))
                .foregroundColor(DesignSystem.Colors.textTertiary)

            VStack(spacing: 6) {
                Text("Build Your Profile")
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                Text("Read and save articles to teach Signal what you care about")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Progress indicator
            HStack(spacing: 8) {
                ForEach(0..<5, id: \.self) { i in
                    Circle()
                        .fill(i < interactionCount ? DesignSystem.Colors.accent : DesignSystem.Colors.border)
                        .frame(width: 8, height: 8)
                }
            }
            Text("\(interactionCount) of 5 interactions")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.xl)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Learning state (5-10 interactions, low confidence)

    private var learningStateView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(DesignSystem.Colors.accent)
            Text("Signal is learning your interests…")
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.textSecondary)
            Text("\(interactionCount) interactions recorded")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.xl)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Full profile view

    private func profileView(_ profile: TasteProfile) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {

            // Confidence bar
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Profile confidence")
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    Spacer()
                    Text("\(profile.confidencePercent)%")
                        .font(DesignSystem.Typography.monoLarge)
                        .foregroundColor(DesignSystem.Colors.accent)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(DesignSystem.Colors.surfaceElevated)
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(DesignSystem.Colors.accent)
                            .frame(
                                width: geo.size.width * CGFloat(profile.confidenceScore),
                                height: 6
                            )
                            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: profile.confidenceScore)
                    }
                }
                .frame(height: 6)
            }
            .padding(DesignSystem.Spacing.lg)
            .background(DesignSystem.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Profile text snippet
            let sentences = profile.profileText
                .components(separatedBy: ".")
                .prefix(2)
                .joined(separator: ".")
                .trimmingCharacters(in: .whitespaces)

            if !sentences.isEmpty {
                Text("\(sentences).")
                    .font(DesignSystem.Typography.body.italic())
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .padding(DesignSystem.Spacing.lg)
                    .background(DesignSystem.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Interest pills
            if !profile.topInterests.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("TOP INTERESTS")
                        .font(DesignSystem.Typography.label)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                        .kerning(1)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(profile.topInterests, id: \.key) { interest in
                                HStack(spacing: 4) {
                                    Text(interest.key)
                                        .font(.system(size: 12, weight: .medium))
                                    Text("\(Int(interest.value * 100))%")
                                        .font(.system(size: 11, weight: .regular))
                                        .foregroundColor(DesignSystem.Colors.accent.opacity(0.7))
                                }
                                .foregroundColor(DesignSystem.Colors.accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(DesignSystem.Colors.accent.opacity(0.12))
                                .clipShape(Capsule())
                            }
                        }
                    }
                }
                .padding(DesignSystem.Spacing.lg)
                .background(DesignSystem.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Key entity pills by type
            entitySection("MODELS", items: profile.keyEntities.models)
            entitySection("BENCHMARKS", items: profile.keyEntities.benchmarks)
            entitySection("TECHNIQUES", items: profile.keyEntities.techniques)
        }
    }

    private func entitySection(_ label: String, items: [String]) -> some View {
        Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(label)
                        .font(DesignSystem.Typography.label)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                        .kerning(1)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(items, id: \.self) { item in
                                Text(item)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .overlay(
                                        Capsule().stroke(DesignSystem.Colors.border, lineWidth: 1)
                                    )
                            }
                        }
                    }
                }
                .padding(DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - Stats row (always shown)

    private var statsRow: some View {
        HStack {
            statCell(value: "\(stats.interactionCount)", label: "INTERACTIONS")
            Divider().frame(height: 40).background(DesignSystem.Colors.border)
            statCell(value: "\(stats.articlestoday)", label: "TODAY")
            Divider().frame(height: 40).background(DesignSystem.Colors.border)
            statCell(value: "\(stats.breakingToday)", label: "BREAKING")
        }
        .padding(DesignSystem.Spacing.lg)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundColor(DesignSystem.Colors.textPrimary)
            Text(label)
                .font(DesignSystem.Typography.label)
                .foregroundColor(DesignSystem.Colors.textTertiary)
                .kerning(0.5)
        }
        .frame(maxWidth: .infinity)
    }
}

private func sectionHeader(_ title: String) -> some View {
    Text(title)
        .font(DesignSystem.Typography.label)
        .foregroundColor(DesignSystem.Colors.textTertiary)
        .kerning(2)
}
