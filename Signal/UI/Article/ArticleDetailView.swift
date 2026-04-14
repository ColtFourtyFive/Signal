import SwiftUI
import SafariServices

struct ArticleDetailView: View {
    let article: Article
    var namespace: Namespace.ID? = nil

    @State private var viewModel: ArticleViewModel
    @State private var showSafari = false
    @Environment(\.dismiss) private var dismiss

    init(article: Article, namespace: Namespace.ID? = nil) {
        self.article = article
        self.namespace = namespace
        _viewModel = State(initialValue: ArticleViewModel(article: article))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            DesignSystem.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Score badge (matched geometry destination)
                    HStack {
                        let badge = ScoreBadgeView(score: article.safeScore, large: true)
                        if let ns = namespace {
                            badge.matchedGeometryEffect(id: "score-\(article.id)", in: ns)
                        } else {
                            badge
                        }

                        Spacer()

                        // Primary source badge
                        if article.isPrimarySource {
                            HStack(spacing: 4) {
                                Text("PRIMARY SOURCE")
                                    .font(DesignSystem.Typography.label)
                                    .foregroundColor(DesignSystem.Colors.accent)
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(DesignSystem.Colors.accent)
                            }
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.xl)
                    .padding(.top, DesignSystem.Spacing.xl)

                    // Category
                    if let category = article.category {
                        CategoryPillView(category: category, small: false)
                            .padding(.horizontal, DesignSystem.Spacing.xl)
                            .padding(.top, DesignSystem.Spacing.md)
                    }

                    // Title
                    Text(article.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .padding(.horizontal, DesignSystem.Spacing.xl)
                        .padding(.top, DesignSystem.Spacing.md)

                    // Source + date
                    HStack(spacing: 8) {
                        Text(article.feedName.uppercased())
                            .font(DesignSystem.Typography.mono)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        Text("·")
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                        if let date = article.publishedAt {
                            Text(date.shortDateTime)
                                .font(DesignSystem.Typography.mono)
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.xl)
                    .padding(.top, DesignSystem.Spacing.sm)

                    // Key entities
                    if !article.entities.isEmpty {
                        EntityPillsView(entities: article.entities)
                            .padding(.top, DesignSystem.Spacing.md)
                    }

                    // Divider
                    Rectangle()
                        .fill(DesignSystem.Colors.border)
                        .frame(height: 0.5)
                        .padding(.horizontal, DesignSystem.Spacing.xl)
                        .padding(.top, DesignSystem.Spacing.lg)

                    // Why this matters
                    if let reason = article.scoreReason {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("WHY THIS MATTERS")
                                .font(DesignSystem.Typography.label)
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                                .kerning(1)

                            Text(reason)
                                .font(.system(size: 15, weight: .regular).italic())
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                        .padding(.horizontal, DesignSystem.Spacing.xl)
                        .padding(.top, DesignSystem.Spacing.lg)
                    }

                    // Divider
                    Rectangle()
                        .fill(DesignSystem.Colors.border)
                        .frame(height: 0.5)
                        .padding(.horizontal, DesignSystem.Spacing.xl)
                        .padding(.top, DesignSystem.Spacing.lg)

                    // Article content
                    if let content = article.content, !content.isEmpty {
                        Text(content)
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .textSelection(.enabled)
                            .lineSpacing(4)
                            .padding(.horizontal, DesignSystem.Spacing.xl)
                            .padding(.top, DesignSystem.Spacing.lg)
                    }

                    // Read full article button
                    Button {
                        showSafari = true
                    } label: {
                        HStack {
                            Text("Read Full Article")
                                .font(.system(size: 16, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(DesignSystem.Colors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(.horizontal, DesignSystem.Spacing.xl)
                    .padding(.top, DesignSystem.Spacing.xl)
                    .padding(.bottom, 100) // space for bottom bar
                }
            }

            // Fixed bottom action bar
            bottomBar
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DesignSystem.Colors.background, for: .navigationBar)
        .sheet(isPresented: $showSafari) {
            if let url = URL(string: article.url) {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
        .onAppear { viewModel.startReading() }
        .onDisappear { viewModel.stopReading() }
    }

    // MARK: - Bottom bar
    private var bottomBar: some View {
        HStack(spacing: 0) {
            // Save/Unsave
            Button {
                viewModel.toggleSave()
                HapticService.impact(.medium)
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: viewModel.article.isSaved ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 20))
                        .foregroundColor(viewModel.article.isSaved ? DesignSystem.Colors.accent : DesignSystem.Colors.textSecondary)
                    Text(viewModel.article.isSaved ? "Saved" : "Save")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            // Share
            if let url = URL(string: article.url) {
                ShareLink(item: url) {
                    VStack(spacing: 3) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 20))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        Text("Share")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded { _ in
                    _ = viewModel.share()
                })
            }

            // Dismiss
            Button {
                HapticService.impact(.light)
                dismiss()
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    Text("Dismiss")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .fill(DesignSystem.Colors.border)
                .frame(height: 0.5),
            alignment: .top
        )
    }
}

// MARK: - Safari wrapper
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
