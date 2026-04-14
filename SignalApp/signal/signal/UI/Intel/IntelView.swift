import SwiftUI

struct IntelView: View {
    @State private var viewModel = IntelViewModel()
    @State private var selectedTab: IntelTab = .taste

    enum IntelTab: String, CaseIterable {
        case taste    = "Taste"
        case discover = "Discovery"
        case sources  = "Sources"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()

                if viewModel.isLoading {
                    FullScreenLoadingView()
                } else {
                    content
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Text("INTEL")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await viewModel.load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
            }
        }
        .task { await viewModel.load() }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.xxl) {
                // Segmented tab picker
                Picker("Section", selection: $selectedTab) {
                    ForEach(IntelTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.top, DesignSystem.Spacing.lg)

                // Tab content
                Group {
                    switch selectedTab {
                    case .taste:
                        if let stats = viewModel.stats {
                            TasteProfileView(
                                stats: stats,
                                profile: viewModel.tasteProfile,
                                interactionCount: viewModel.profileInteractionCount
                            )
                        } else {
                            noDataView
                        }
                    case .discover:
                        DiscoveryView(viewModel: viewModel)
                    case .sources:
                        SourceHealthView(viewModel: viewModel)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.bottom, DesignSystem.Spacing.xxl)
            }
        }
        .background(DesignSystem.Colors.background)
        .refreshable { await viewModel.load() }
    }

    private var noDataView: some View {
        EmptyStateView(
            icon: "chart.bar",
            title: "No data yet",
            subtitle: "Start reading articles to build your profile"
        )
    }
}
