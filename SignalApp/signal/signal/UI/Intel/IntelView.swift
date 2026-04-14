import SwiftUI

struct IntelView: View {
    @State private var viewModel = IntelViewModel()
    @State private var selectedTab: IntelTab = .taste
    @State private var showTasteTuner = false

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
        .sheet(isPresented: $showTasteTuner) {
            TasteTunerView(onComplete: { showTasteTuner = false }, isSheet: true)
                .preferredColorScheme(.dark)
        }
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
                        // Taste Tuner button card
                        Button {
                            showTasteTuner = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("TASTE TUNER")
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .foregroundColor(DesignSystem.Colors.accent)
                                    Text("Re-calibrate your feed in 15 swipes")
                                        .font(.system(size: 14))
                                        .foregroundColor(DesignSystem.Colors.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14))
                                    .foregroundColor(DesignSystem.Colors.textTertiary)
                            }
                            .padding(16)
                            .background(DesignSystem.Colors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(DesignSystem.Colors.border, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)

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
