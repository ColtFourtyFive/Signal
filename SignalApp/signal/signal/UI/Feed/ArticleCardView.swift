import SwiftUI

struct ArticleCardView: View {
    let article: Article
    var namespace: Namespace.ID? = nil
    var onSave: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top row: source + time + score
            HStack(alignment: .center, spacing: 0) {
                // Score dot + source name
                HStack(spacing: 5) {
                    Circle()
                        .fill(DesignSystem.Colors.score(article.safeScore))
                        .frame(width: 7, height: 7)
                    Text(article.feedName.uppercased())
                        .font(DesignSystem.Typography.mono)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 8) {
                    if let date = article.publishedAt {
                        Text(date.relativeDisplay)
                            .font(DesignSystem.Typography.mono)
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                    }

                    // External link icon
                    if let url = URL(string: article.url) {
                        Link(destination: url) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                        }
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.top, 14)

            // Title
            Text(article.title)
                .font(DesignSystem.Typography.headline)
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .lineLimit(3)
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.top, 8)

            // Score reason
            if let reason = article.scoreReason {
                Text(reason)
                    .font(.system(size: 13, weight: .regular).italic())
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                    .lineLimit(2)
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.top, 5)
            }

            // Bottom row: category + score badge
            HStack(alignment: .center, spacing: 8) {
                if let category = article.category {
                    CategoryPillView(category: category)
                }

                // Primary source indicator
                if article.isPrimarySource {
                    Text("PRIMARY")
                        .font(DesignSystem.Typography.label)
                        .foregroundColor(DesignSystem.Colors.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(DesignSystem.Colors.accent.opacity(0.5), lineWidth: 0.5)
                        )
                }

                Spacer()

                // "For you" tag when personalization score is high
                if let pscore = article.personalizationScore, pscore >= 0.7 {
                    Text("For you")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DesignSystem.Colors.accent.opacity(0.12))
                        .clipShape(Capsule())
                }

                let badge = ScoreBadgeView(score: article.safeScore)
                if let ns = namespace {
                    badge.matchedGeometryEffect(id: "score-\(article.id)", in: ns)
                } else {
                    badge
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .cardStyle()
        .contentShape(Rectangle())
    }
}
