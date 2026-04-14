import SwiftUI

struct FeedView: View {
    @State private var viewModel = FeedViewModel()
    @Namespace private var heroNamespace

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()

                if viewModel.isLoading && viewModel.articles.isEmpty {
                    FullScreenLoadingView()
                } else if viewModel.articles.isEmpty && !viewModel.isLoading {
                    EmptyStateView(
                        icon: "bolt.slash",
                        title: "No signal yet",
                        subtitle: "Pull to refresh or check your feed sources",
                        actionTitle: "Refresh",
                        action: { Task { await viewModel.refresh() } }
                    )
                } else {
                    feedList
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .navigationDestination(for: Article.self) { article in
                ArticleDetailView(article: article, namespace: heroNamespace)
            }
        }
        .task { await viewModel.loadInitial() }
    }

    // MARK: - Feed list
    private var feedList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Offline banner
                if viewModel.isOffline {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 12))
                        Text("Showing cached articles")
                            .font(DesignSystem.Typography.caption)
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.8))
                }

                // Breaking bar — only when score 9-10 articles exist
                BreakingBarView(articles: viewModel.breakingArticles) { _ in }
                    .animation(DesignSystem.Animation.spring, value: viewModel.breakingArticles.isEmpty)

                // Category filter
                FilterPillsView(selected: Binding(
                    get: { viewModel.selectedCategory },
                    set: { viewModel.selectCategory($0) }
                ))

                // Articles
                ForEach(viewModel.filteredArticles) { article in
                    NavigationLink(value: article) {
                        ArticleCardView(
                            article: article,
                            namespace: heroNamespace
                        )
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            HapticService.impact(.heavy)
                            viewModel.save(article)
                        } label: {
                            Label("Save", systemImage: "bookmark.fill")
                        }
                        .tint(DesignSystem.Colors.accent)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            HapticService.impact(.medium)
                            viewModel.dismiss(article)
                        } label: {
                            Label("Dismiss", systemImage: "xmark")
                        }
                        .tint(DesignSystem.Colors.critical)
                    }
                    .onAppear {
                        // Infinite scroll trigger
                        if article.id == viewModel.filteredArticles.last?.id {
                            Task { await viewModel.loadMore() }
                        }
                    }
                }

                // Loading more indicator
                if viewModel.hasMore && !viewModel.filteredArticles.isEmpty && viewModel.searchQuery.isEmpty {
                    LoadingView()
                }
            }
        }
        .searchable(text: $viewModel.searchQuery, prompt: "Search articles")
        .task(id: viewModel.searchQuery) {
            if viewModel.searchQuery.isEmpty {
                viewModel.filteredArticles = viewModel.articles
                return
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await viewModel.search(viewModel.searchQuery)
        }
        .refreshable {
            await viewModel.refresh()
        }
        .background(DesignSystem.Colors.background)
    }

    // MARK: - Toolbar
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Text("SIGNAL")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(DesignSystem.Colors.textPrimary)
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                HapticService.impact(.light)
                Task { await viewModel.refresh() }
            } label: {
                Image(systemName: viewModel.isRefreshing ? "arrow.clockwise.circle.fill" : "arrow.clockwise")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .rotationEffect(.degrees(viewModel.isRefreshing ? 360 : 0))
                    .animation(
                        viewModel.isRefreshing
                            ? .linear(duration: 1).repeatForever(autoreverses: false)
                            : .default,
                        value: viewModel.isRefreshing
                    )
            }
        }
    }
}
