import SwiftUI

// パラパラモード（B3）: 本が無くても、付箋のあるページを順にめくり、
// 周辺の文章で「この話だった」と思い出す。見た目は本を読む画面のように白いページ。
struct FlipView: View {
    let stickies: [Sticky]   // 配置済み・ページ順
    let bookTitle: String
    var onClose: () -> Void
    @State private var index = 0

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button { onClose() } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 36, height: 36)
                            .background(Theme.card, in: Circle())
                    }
                    .accessibilityLabel("閉じる")
                    Spacer()
                    Text(bookTitle)
                        .font(.caption)
                        .foregroundStyle(Theme.subInk)
                        .lineLimit(1)
                    Spacer()
                    Color.clear.frame(width: 36, height: 36)
                }
                .padding(.horizontal, 18).padding(.top, 8)

                if stickies.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "book.pages").font(.largeTitle).foregroundStyle(Theme.subInk)
                        Text("まだ付箋がありません").foregroundStyle(Theme.subInk)
                    }
                    Spacer()
                } else {
                    TabView(selection: $index) {
                        ForEach(Array(stickies.enumerated()), id: \.element.id) { i, s in
                            FlipPage(sticky: s).tag(i)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))

                    Text("\(index + 1) / \(stickies.count)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(Theme.subInk)
                        .padding(.bottom, 10)
                }
            }
        }
    }
}

private struct FlipPage: View {
    let sticky: Sticky

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    CategoryLabel(color: sticky.color)
                    Spacer()
                    Text("p.\(sticky.pageNumber)").font(.footnote).foregroundStyle(Theme.subInk)
                }

                // 本のページのように、周りの文と付箋の行を続けて組む
                Text(pageText)
                    .font(Theme.serif(.title3))
                    .lineSpacing(10)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    Text(sticky.heading).font(.headline).foregroundStyle(Theme.ink)
                    if !sticky.memo.isEmpty {
                        Text(sticky.memo)
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink)
                            .lineSpacing(4)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(sticky.color.color.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var pageText: AttributedString {
        var result = AttributedString()
        for line in sticky.clipBefore {
            var t = AttributedString(line + "\n")
            t.foregroundColor = Theme.subInk
            result += t
        }
        var marker = AttributedString(sticky.marker)
        marker.foregroundColor = Theme.ink
        marker.backgroundColor = sticky.color.color.opacity(0.4)
        result += marker
        for line in sticky.clipAfter {
            var t = AttributedString("\n" + line)
            t.foregroundColor = Theme.subInk
            result += t
        }
        return result
    }
}
