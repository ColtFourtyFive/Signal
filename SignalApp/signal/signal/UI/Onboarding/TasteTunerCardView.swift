import SwiftUI

struct TasteTunerCardView: View {
    let article: Article
    var onRate: (TasteTier) -> Void

    @State private var offset: CGSize = .zero
    @State private var rotation: Double = 0

    // Detect drag direction
    private var horizontalProgress: Double { Double(offset.width) / 100.0 }
    private var verticalProgress: Double { Double(-offset.height) / 100.0 }

    private var isSwipingRight: Bool { offset.width > 30 && abs(offset.width) > abs(offset.height) }
    private var isSwipingLeft: Bool  { offset.width < -30 && abs(offset.width) > abs(offset.height) }
    private var isSwipingUp: Bool    { offset.height < -30 && abs(offset.height) > abs(offset.width) }

    private var dominantTier: TasteTier? {
        if isSwipingUp   { return .mustRead }
        if isSwipingRight { return .interesting }
        if isSwipingLeft  { return .skip }
        return nil
    }

    var body: some View {
        ZStack {
            // Background tint
            RoundedRectangle(cornerRadius: 16)
                .fill(backgroundTint)
                .animation(.interactiveSpring(), value: offset)

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
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .lineLimit(5)

                // Score reason
                if let reason = article.scoreReason {
                    Text(reason)
                        .font(.system(size: 14).italic())
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                        .lineLimit(2)
                }

                Spacer()

                // Swipe hint stamps
                ZStack {
                    // SKIP (left)
                    HStack {
                        stampView(text: "SKIP", color: .red, opacity: isSwipingLeft ? min(1, abs(horizontalProgress)) : 0)
                        Spacer()
                    }

                    // INTERESTING (right)
                    HStack {
                        Spacer()
                        stampView(text: "INTERESTING", color: .orange, opacity: isSwipingRight ? min(1, horizontalProgress) : 0)
                    }

                    // MUST READ (up)
                    VStack {
                        stampView(text: "MUST READ ★", color: DesignSystem.Colors.accent, opacity: isSwipingUp ? min(1, verticalProgress) : 0)
                        Spacer()
                    }
                }
                .frame(height: 44)
            }
            .padding(20)
        }
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(borderColor, lineWidth: dominantTier != nil ? 1.5 : 0.5)
                .animation(.interactiveSpring(), value: offset)
        )
        .offset(offset)
        .rotationEffect(.degrees(rotation))
        .gesture(dragGesture)
    }

    // MARK: - Helpers

    private var backgroundTint: Color {
        let strength = min(0.15, max(abs(horizontalProgress), verticalProgress) * 0.15)
        if isSwipingUp    { return DesignSystem.Colors.accent.opacity(strength) }
        if isSwipingRight { return Color.orange.opacity(strength) }
        if isSwipingLeft  { return Color.red.opacity(strength) }
        return Color.clear
    }

    private var borderColor: Color {
        switch dominantTier {
        case .mustRead:    return DesignSystem.Colors.accent
        case .interesting: return .orange
        case .skip:        return .red
        case nil:          return DesignSystem.Colors.border
        }
    }

    private func stampView(text: String, color: Color, opacity: Double) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(color, lineWidth: 2))
            .opacity(opacity)
    }

    // MARK: - Gesture

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = value.translation
                // Only rotate on horizontal swipes
                let horizontalDominance = abs(value.translation.width) > abs(value.translation.height)
                rotation = horizontalDominance ? Double(value.translation.width / 20) : 0
            }
            .onEnded { value in
                let threshold: CGFloat = 80
                let dx = value.translation.width
                let dy = value.translation.height

                if abs(dy) > threshold && -dy > abs(dx) {
                    // Swipe up → Must Read
                    flyOff(tier: .mustRead, translation: value.translation)
                } else if dx > threshold && abs(dx) > abs(dy) {
                    // Swipe right → Interesting
                    flyOff(tier: .interesting, translation: value.translation)
                } else if dx < -threshold && abs(dx) > abs(dy) {
                    // Swipe left → Skip
                    flyOff(tier: .skip, translation: value.translation)
                } else {
                    snapBack()
                }
            }
    }

    private func flyOff(tier: TasteTier, translation: CGSize) {
        let dx = translation.width
        let dy = translation.height

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            switch tier {
            case .mustRead:
                offset = CGSize(width: dx * 0.3, height: -800)
                rotation = 0
            case .interesting:
                offset = CGSize(width: 700, height: dy)
                rotation = 20
            case .skip:
                offset = CGSize(width: -700, height: dy)
                rotation = -20
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            onRate(tier)
        }
    }

    private func snapBack() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            offset = .zero
            rotation = 0
        }
    }
}
