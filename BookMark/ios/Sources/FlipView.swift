import SwiftUI

// パラパラモード（B3）: 本が無くても、付箋のあるページを順にめくり、
// 周辺の文章で「この話だった」と思い出す。
struct FlipView: View {
    let stickies: [Sticky]   // 配置済み・ページ順
    let bookTitle: String
    var onClose: () -> Void
    @State private var index = 0

    var body: some View {
        ZStack {
            Color(red: 0.11, green: 0.102, blue: 0.086).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button("閉じる") { onClose() }
                        .font(.subheadline).bold()
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.white.opacity(0.15))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Spacer()
                    if !stickies.isEmpty {
                        Text("\(index + 1) / \(stickies.count) ・ \(bookTitle)")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 18).padding(.top, 12)

                if stickies.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Text("🪶").font(.system(size: 40))
                        Text("まだ付箋がありません")
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                } else {
                    TabView(selection: $index) {
                        ForEach(Array(stickies.enumerated()), id: \.element.id) { i, s in
                            FlipCard(sticky: s).tag(i)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                }
            }
        }
    }
}

private struct FlipCard: View {
    let sticky: Sticky
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("p.\(sticky.pageNumber)")
                    .font(.subheadline).bold()
                    .foregroundStyle(.white.opacity(0.6))

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(sticky.clipBefore, id: \.self) {
                        Text($0).foregroundStyle(.white.opacity(0.75))
                    }
                    Text(sticky.marker)
                        .bold().foregroundStyle(.white)
                        .padding(.bottom, 3)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(sticky.color.color).frame(height: 3)
                        }
                    ForEach(sticky.clipAfter, id: \.self) {
                        Text($0).foregroundStyle(.white.opacity(0.75))
                    }
                }
                .font(.body)
                .lineSpacing(6)

                HStack(spacing: 10) {
                    Circle().fill(sticky.color.color).frame(width: 14, height: 14)
                    Text(sticky.heading).font(.title3).bold().foregroundStyle(.white)
                }
                .padding(.top, 8)

                if !sticky.memo.isEmpty {
                    Text(sticky.memo)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
