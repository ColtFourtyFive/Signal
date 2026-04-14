import SwiftUI

struct OnboardingView: View {
    var onComplete: () -> Void

    @State private var viewModel = OnboardingViewModel()

    var body: some View {
        ZStack {
            DesignSystem.Colors.background.ignoresSafeArea()

            switch viewModel.currentScreen {
            case .welcome:
                welcomeScreen
                    .transition(.opacity)
            case .calibration:
                calibrationScreen
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .generating:
                generatingScreen
                    .transition(.opacity)
                    .task { await waitThenComplete() }
            }
        }
        .animation(.easeInOut(duration: 0.4), value: viewModel.currentScreen)
    }

    // MARK: - Screen 1: Welcome

    private var welcomeScreen: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "bolt.fill")
                .font(.system(size: 60, weight: .bold))
                .foregroundColor(DesignSystem.Colors.accent)

            VStack(spacing: 10) {
                Text("SIGNAL")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Text("Your personal AI intelligence feed")
                    .font(.system(size: 17))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    HapticService.impact(.light)
                    withAnimation {
                        viewModel.currentScreen = .calibration
                    }
                    Task { await viewModel.loadCalibrationArticles() }
                } label: {
                    Text("Getting started →")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(DesignSystem.Colors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Text("Takes 60 seconds")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Screen 2: Calibration

    private var calibrationScreen: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 6) {
                Text("What's signal to you?")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Text("Swipe right on articles you'd want to read.\nSwipe left on ones you'd skip.")
                    .font(.system(size: 15))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 56)
            .padding(.horizontal, 24)

            // Progress
            VStack(spacing: 8) {
                Text("\(viewModel.currentIndex + 1) of \(max(1, viewModel.calibrationArticles.count))")
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
            .padding(.top, 20)

            Spacer()

            // Card
            if viewModel.isLoadingArticles {
                ProgressView()
                    .tint(DesignSystem.Colors.accent)
                    .scaleEffect(1.5)
            } else if let article = viewModel.currentArticle {
                CalibrationCardView(article: article) { liked in
                    viewModel.swipe(liked: liked)
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
                        Task { await viewModel.loadCalibrationArticles() }
                    }
                    .foregroundColor(DesignSystem.Colors.accent)
                }
            }

            Spacer()

            // Tap buttons (alternative to swipe)
            if !viewModel.isLoadingArticles && viewModel.currentArticle != nil {
                HStack(spacing: 24) {
                    Button {
                        viewModel.swipe(liked: false)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark")
                            Text("Skip")
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(DesignSystem.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        viewModel.swipe(liked: true)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark")
                            Text("Signal")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(DesignSystem.Colors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 24)
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
                Text("Building your profile…")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Text("Signal is learning what matters to you")
                    .font(.system(size: 15))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            Spacer()
        }
    }

    // Wait for profile generation (max 8s) then hand off to main app
    private func waitThenComplete() async {
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        onComplete()
    }
}
