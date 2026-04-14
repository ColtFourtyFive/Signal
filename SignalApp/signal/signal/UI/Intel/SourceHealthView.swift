import SwiftUI

struct SourceHealthView: View {
    @Bindable var viewModel: IntelViewModel
    @State private var selectedFeed: Feed? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            sectionHeader("SOURCE HEALTH")

            VStack(spacing: 0) {
                ForEach(viewModel.feeds) { feed in
                    feedRow(feed)
                        .onTapGesture { selectedFeed = feed }
                    if feed.id != viewModel.feeds.last?.id {
                        Rectangle()
                            .fill(DesignSystem.Colors.border)
                            .frame(height: 0.5)
                            .padding(.horizontal, DesignSystem.Spacing.lg)
                    }
                }
            }
            .background(DesignSystem.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .sheet(item: $selectedFeed) { feed in
            FeedDetailSheet(feed: feed, viewModel: viewModel)
        }
    }

    private func feedRow(_ feed: Feed) -> some View {
        HStack(spacing: 12) {
            // Health indicator (broken = red, low quality = orange, good/fair = based on score)
            Circle()
                .fill(healthDotColor(feed))
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 2) {
                Text(feed.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(feed.categoryDisplay)
                        .font(DesignSystem.Typography.mono)
                        .foregroundColor(DesignSystem.Colors.textTertiary)

                    Text("·")
                        .foregroundColor(DesignSystem.Colors.textTertiary)

                    if let fetched = feed.lastFetchedAt {
                        Text(fetched.relativeDisplay)
                            .font(DesignSystem.Typography.mono)
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                    } else {
                        Text("never fetched")
                            .font(DesignSystem.Typography.mono)
                            .foregroundColor(DesignSystem.Colors.critical.opacity(0.7))
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f", feed.avgScore))
                    .font(DesignSystem.Typography.monoLarge)
                    .foregroundColor(DesignSystem.Colors.score(feed.avgScore))
                Text("\(feed.articleCount) articles")
                    .font(DesignSystem.Typography.mono)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11))
                .foregroundColor(DesignSystem.Colors.textTertiary)
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func healthDotColor(_ feed: Feed) -> Color {
        if feed.isBroken { return DesignSystem.Colors.critical }
        if feed.isLowQuality { return DesignSystem.Colors.high }
        switch feed.healthStatus {
        case .good:  return DesignSystem.Colors.accent
        case .fair:  return DesignSystem.Colors.high
        case .poor:  return DesignSystem.Colors.critical
        }
    }
}

// MARK: - Feed Detail Sheet

struct FeedDetailSheet: View {
    let feed: Feed
    @Bindable var viewModel: IntelViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                        // URL
                        Text(feed.url)
                            .font(DesignSystem.Typography.mono)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .lineLimit(2)
                            .padding(DesignSystem.Spacing.lg)
                            .background(DesignSystem.Colors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        // Stats
                        HStack {
                            statCell(value: "\(feed.articleCount)", label: "ARTICLES")
                            Divider().frame(height: 40).background(DesignSystem.Colors.border)
                            statCell(value: String(format: "%.1f", feed.avgScore), label: "AVG SCORE")
                            if let fetched = feed.lastFetchedAt {
                                Divider().frame(height: 40).background(DesignSystem.Colors.border)
                                statCell(value: fetched.relativeDisplay, label: "LAST FETCH")
                            }
                        }
                        .padding(DesignSystem.Spacing.lg)
                        .background(DesignSystem.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        // Warnings
                        if feed.isBroken {
                            warningBanner(
                                icon: "exclamationmark.triangle.fill",
                                message: "This feed hasn't updated in over 48 hours",
                                color: DesignSystem.Colors.critical
                            )
                        } else if feed.isLowQuality {
                            warningBanner(
                                icon: "chart.bar.fill",
                                message: "Consistently low-quality articles (avg score < 4.5)",
                                color: DesignSystem.Colors.high
                            )
                        }

                        // Remove button
                        Button {
                            showDeleteConfirm = true
                        } label: {
                            Text("Remove Feed")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.critical)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(DesignSystem.Colors.critical.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(DesignSystem.Spacing.lg)
                }
            }
            .navigationTitle(feed.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(DesignSystem.Colors.accent)
                }
            }
            .alert("Remove \(feed.name)?", isPresented: $showDeleteConfirm) {
                Button("Remove", role: .destructive) {
                    viewModel.deleteFeed(feed)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will stop fetching articles from this source.")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(DesignSystem.Typography.label)
                .foregroundColor(DesignSystem.Colors.textTertiary)
                .kerning(0.5)
        }
        .frame(maxWidth: .infinity)
    }

    private func warningBanner(icon: String, message: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(message)
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .padding(DesignSystem.Spacing.lg)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private func sectionHeader(_ title: String) -> some View {
    Text(title)
        .font(DesignSystem.Typography.label)
        .foregroundColor(DesignSystem.Colors.textTertiary)
        .kerning(2)
}
