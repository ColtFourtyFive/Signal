import SwiftUI

struct BreakingBarView: View {
    let articles: [Article]
    var onTap: (Article) -> Void = { _ in }

    @State private var dotOpacity: Double = 1.0
    @State private var currentIndex: Int = 0

    private let timer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        if !articles.isEmpty {
            currentArticleRow
                .frame(height: 40)
                .background(DesignSystem.Colors.critical.opacity(0.08))
                .overlay(
                    Rectangle()
                        .fill(DesignSystem.Colors.critical.opacity(0.3))
                        .frame(height: 0.5),
                    alignment: .bottom
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                        dotOpacity = 0.2
                    }
                }
                .onReceive(timer) { _ in
                    guard articles.count > 1 else { return }
                    withAnimation(.easeInOut(duration: 0.5)) {
                        currentIndex = (currentIndex + 1) % articles.count
                    }
                }
        }
    }

    private var currentArticleRow: some View {
        let article = articles[min(currentIndex, articles.count - 1)]
        return Button { onTap(article) } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(DesignSystem.Colors.critical)
                    .frame(width: 6, height: 6)
                    .opacity(dotOpacity)

                Text(article.feedName.uppercased())
                    .font(DesignSystem.Typography.mono)
                    .foregroundColor(DesignSystem.Colors.critical)
                    .lineLimit(1)

                Text("·")
                    .foregroundColor(DesignSystem.Colors.textTertiary)

                Text(article.title)
                    .font(DesignSystem.Typography.mono)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)

                Spacer()

                if articles.count > 1 {
                    Text("\(currentIndex + 1)/\(articles.count)")
                        .font(DesignSystem.Typography.mono)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
        }
        .buttonStyle(.plain)
        .id(article.id)
    }
}
