import SwiftUI

struct TasteTunerView: View {
    var onComplete: () -> Void
    var isSheet: Bool = false

    @State private var viewModel = TasteTunerViewModel()

    var body: some View {
        ZStack {
            DesignSystem.Colors.background.ignoresSafeArea()

            switch viewModel.currentScreen {
            case .intro:
                introScreen
                    .transition(.opacity)
            case .tuning:
                tuningScreen
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .generating:
                generatingScreen
                    .transition(.opacity)
                    .task { await waitForResults() }
            case .results:
                resultsScreen
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: viewModel.currentScreen)
    }

    // MARK: - Screen 1: Intro

    private var introScreen: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon + title
            VStack(spacing: 16) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.accent)

                VStack(spacing: 8) {
                    Text("TASTE TUNER")
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    Text("Rate 15 articles to calibrate your feed")
                        .font(.system(size: 16))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer()

            // Gesture instructions
            VStack(spacing: 0) {
                Text("HOW IT WORKS")
                    .font(DesignSystem.Typography.label)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 12)

                VStack(spacing: 2) {
                    GestureExplanationRow(
                        symbol: "arrow.up",
                        gesture: "Swipe up",
                        label: "Must Read",
                        color: DesignSystem.Colors.accent
                    )
                    GestureExplanationRow(
                        symbol: "arrow.right",
                        gesture: "Swipe right",
                        label: "Interesting",
                        color: .orange
                    )
                    GestureExplanationRow(
                        symbol: "arrow.left",
                        gesture: "Swipe left",
                        label: "Skip",
                        color: DesignSystem.Colors.critical
                    )
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            // CTA
            VStack(spacing: 12) {
                Button {
                    HapticService.impact(.medium)
                    withAnimation {
                        viewModel.currentScreen = .tuning
                    }
                    Task { await viewModel.loadArticles() }
                } label: {
                    Text("Start Tuning →")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(DesignSystem.Colors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if isSheet {
                    Button("Maybe later") {
                        onComplete()
                    }
                    .font(.system(size: 15))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                }

                Text("Takes about 2 minutes")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 52)
        }
    }

    // MARK: - Screen 2: Tuning

    private var tuningScreen: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 6) {
                Text("Rate this article")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Text("↑ Must Read  ·  → Interesting  ·  ← Skip")
                    .font(.system(size: 13))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 52)
            .padding(.horizontal, 24)

            // Progress
            VStack(spacing: 8) {
                Text("\(viewModel.currentIndex + 1) of \(max(1, viewModel.articles.count))")
                    .font(DesignSystem.Typography.mono)
                    .foregroundColor(DesignSystem.Colors.textTertiary)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(DesignSystem.Colors.border)
                            .frame(height: 3)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(DesignSystem.Colors.accent)
                            .frame(width: geo.size.width * viewModel.progress, height: 3)
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.progress)
                    }
                }
                .frame(height: 3)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Spacer()

            // Card
            if viewModel.isLoading {
                ProgressView()
                    .tint(DesignSystem.Colors.accent)
                    .scaleEffect(1.5)
            } else if let article = viewModel.currentArticle {
                TasteTunerCardView(article: article) { tier in
                    viewModel.rate(tier)
                }
                .padding(.horizontal, 20)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .opacity
                ))
                .id(article.id)
            } else if viewModel.loadError != nil {
                VStack(spacing: 12) {
                    Text("Couldn't load articles")
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    Button("Try again") {
                        Task { await viewModel.loadArticles() }
                    }
                    .foregroundColor(DesignSystem.Colors.accent)
                }
            }

            Spacer()

            // Tap buttons (alternative to swipe)
            if !viewModel.isLoading && viewModel.currentArticle != nil {
                HStack(spacing: 10) {
                    RatingButton(label: "Skip", icon: "xmark", color: DesignSystem.Colors.critical, style: .outline) {
                        viewModel.rate(.skip)
                    }
                    RatingButton(label: "Interesting", icon: "hand.thumbsup", color: .orange, style: .outline) {
                        viewModel.rate(.interesting)
                    }
                    RatingButton(label: "Must Read", icon: "star.fill", color: DesignSystem.Colors.accent, style: .filled) {
                        viewModel.rate(.mustRead)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Screen 3: Generating

    private var generatingScreen: some View {
        VStack(spacing: 20) {
            Spacer()

            ProgressView()
                .tint(DesignSystem.Colors.accent)
                .scaleEffect(1.5)

            VStack(spacing: 8) {
                Text("Calibrating your taste profile…")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Signal is learning what matters to you")
                    .font(.system(size: 15))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Screen 4: Results

    private var resultsScreen: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.accent)

                VStack(spacing: 8) {
                    Text("Profile Tuned")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    Text("Rated \(viewModel.ratings.count) articles")
                        .font(.system(size: 15))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }

                // Tier breakdown pills
                HStack(spacing: 10) {
                    TierSummaryPill(count: viewModel.mustReadCount, label: "Must Read", color: DesignSystem.Colors.accent)
                    TierSummaryPill(count: viewModel.interestingCount, label: "Interesting", color: .orange)
                    TierSummaryPill(count: viewModel.skipCount, label: "Skipped", color: DesignSystem.Colors.textTertiary)
                }
            }

            Spacer()

            Button {
                HapticService.impact(.medium)
                onComplete()
            } label: {
                Text("Start reading →")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(DesignSystem.Colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 52)
        }
    }

    // Wait 2.5s (matches ViewModel sleep) — view just observes currentScreen transition
    private func waitForResults() async {
        // The ViewModel drives the .results transition after its own sleep.
        // No extra wait needed here; this task keeps the .task modifier alive.
        try? await Task.sleep(nanoseconds: 3_000_000_000)
    }
}

// MARK: - Supporting Views

private struct GestureExplanationRow: View {
    let symbol: String
    let gesture: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 28)

            Text(gesture)
                .font(.system(size: 15))
                .foregroundColor(DesignSystem.Colors.textSecondary)

            Spacer()

            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(color)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct RatingButton: View {
    enum Style { case filled, outline }

    let label: String
    let icon: String
    let color: Color
    let style: Style
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(style == .filled ? .black : color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(style == .filled ? color : color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                style == .outline
                    ? RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.4), lineWidth: 1)
                    : nil
            )
        }
    }
}

private struct TierSummaryPill: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(DesignSystem.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
