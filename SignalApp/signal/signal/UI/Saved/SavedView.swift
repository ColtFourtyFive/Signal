import SwiftUI

struct SavedView: View {
    @State private var viewModel = SavedViewModel()
    @Namespace private var heroNamespace

    private let filterCategories: [(id: String?, label: String)] = [
        (nil, "All"),
        ("research_paper", "Research"),
        ("model_release", "Models"),
        ("engineering_post", "Engineering"),
        ("open_source", "Open Source"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()

                if viewModel.isLoading {
                    FullScreenLoadingView()
                } else if viewModel.filteredArticles.isEmpty {
                    EmptyStateView(
                        icon: "bookmark",
                        title: "Nothing saved yet",
                        subtitle: "Swipe right on any article to save it"
                    )
                } else {
                    articleList
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Text("SAVED")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
            }
            .navigationDestination(for: Article.self) { article in
                ArticleDetailView(article: article, namespace: heroNamespace)
            }
        }
        .searchable(text: $viewModel.searchQuery, prompt: "Search saved articles")
        .task { await viewModel.load() }
    }

    private var articleList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Filter pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filterCategories, id: \.label) { item in
                            Button {
                                withAnimation(DesignSystem.Animation.spring) {
                                    viewModel.selectedCategory = item.id
                                }
                            } label: {
                                Text(item.label)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(
                                        viewModel.selectedCategory == item.id
                                            ? .white : DesignSystem.Colors.textSecondary
                                    )
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        viewModel.selectedCategory == item.id
                                            ? DesignSystem.Colors.accent
                                            : DesignSystem.Colors.surfaceElevated
                                    )
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                }

                ForEach(viewModel.filteredArticles) { article in
                    NavigationLink(value: article) {
                        ArticleCardView(article: article, namespace: heroNamespace)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            HapticService.impact(.medium)
                            viewModel.unsave(article)
                        } label: {
                            Label("Remove", systemImage: "bookmark.slash")
                        }
                    }
                }
            }
        }
        .background(DesignSystem.Colors.background)
        .refreshable { await viewModel.load() }
    }
}
