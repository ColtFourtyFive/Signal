import SwiftUI

struct CalibrationCardView: View {
    let article: Article
    var onSwipe: (Bool) -> Void

    @State private var offset: CGSize = .zero
    @State private var rotation: Double = 0

    private var swipeProgress: Double { Double(offset.width) / 120.0 }
    private var isSwipingRight: Bool { offset.width > 20 }
    private var isSwipingLeft: Bool { offset.width < -20 }

    var body: some View {
        ZStack {
            // Background tint based on swipe direction
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    isSwipingRight
                        ? DesignSystem.Colors.accent.opacity(min(0.15, abs(swipeProgress) * 0.15))
                        : isSwipingLeft
                            ? Color.red.opacity(min(0.15, abs(swipeProgress) * 0.15))
                            : Color.clear
                )
                .animation(.interactiveSpring(), value: offset.width)

            VStack(alignment: .leading, spacing: 14) {
                // Score + category + source
                HStack {
                    ScoreBadgeView(score: article.safeScore)
                    if let category = article.category {
                        CategoryPillView(category: category)
                    }
                    Spacer()
                    Text(article.feedName.uppercased())
                        .font(DesignSystem.Typography.mono)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                        .lineLimit(1)
                }

                // Title
                Text(article.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .lineLimit(4)

                // Score reason
                if let reason = article.scoreReason {
                    Text(reason)
                        .font(.system(size: 14).italic())
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                        .lineLimit(2)
                }

                Spacer()

                // Swipe hint overlays
                HStack {
                    Text("SKIP")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.red)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.red, lineWidth: 2))
                        .opacity(isSwipingLeft ? min(1, abs(swipeProgress)) : 0)

                    Spacer()

                    Text("SIGNAL")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(DesignSystem.Colors.accent, lineWidth: 2))
                        .opacity(isSwipingRight ? min(1, swipeProgress) : 0)
                }
            }
            .padding(20)
        }
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(DesignSystem.Colors.border, lineWidth: 0.5))
        .offset(offset)
        .rotationEffect(.degrees(rotation))
        .gesture(dragGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = value.translation
                rotation = Double(value.translation.width / 20)
            }
            .onEnded { value in
                let threshold: CGFloat = 100
                if abs(value.translation.width) > threshold {
                    let liked = value.translation.width > 0
                    flyOff(liked: liked, translation: value.translation)
                } else {
                    snapBack()
                }
            }
    }

    private func flyOff(liked: Bool, translation: CGSize) {
        HapticService.impact(.medium)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            offset = CGSize(
                width: liked ? 600 : -600,
                height: translation.height
            )
            rotation = liked ? 20 : -20
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            onSwipe(liked)
        }
    }

    private func snapBack() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            offset = .zero
            rotation = 0
        }
    }
}
