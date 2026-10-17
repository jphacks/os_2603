import SwiftUI

// 本を横から見た「小口」ビュー（B2）。
// 付箋のあるページ位置に、付箋の色のタブが飛び出して見える。
// タブをタップすると、そのページの付箋一覧へスクロールする。
// 剥がした(mastered)付箋のタブは表示しない。
struct BookSpineView: View {
    let book: Book
    var onSelectPage: (Int) -> Void

    private var groups: [(page: Int, stickies: [Sticky])] {
        let active = book.stickies.filter { $0.placed && !$0.mastered }
        let dict = Dictionary(grouping: active) { $0.pageNumber }
        return dict.keys.sorted().map { ($0, dict[$0]!.sorted { $0.order < $1.order }) }
    }

    var body: some View {
        let maxPage = max(groups.map { $0.page }.max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 4) {
            Text("付箋の位置（本の小口）")
                .font(.caption).foregroundStyle(BooksStyle.subInk)
            GeometryReader { geo in
                let w = geo.size.width
                let barTop = geo.size.height - 24
                ZStack(alignment: .topLeading) {
                    // ページの束（横から見た本）
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(colors: [Color(white: 0.94), Color(white: 0.85)],
                                             startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.black.opacity(0.08)))
                        .frame(height: 24)
                        .offset(y: barTop)
                    // タブ
                    ForEach(groups, id: \.page) { group in
                        let x = maxPage <= 1 ? w / 2
                            : 8 + (CGFloat(group.page) / CGFloat(maxPage)) * (w - 16)
                        Button { onSelectPage(group.page) } label: {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(group.stickies.first!.color.color)
                                .frame(width: 11, height: 30)
                                .overlay(RoundedRectangle(cornerRadius: 2).stroke(.white, lineWidth: 1))
                                .overlay(alignment: .top) {
                                    if group.stickies.count > 1 {
                                        Text("\(group.stickies.count)")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(.black.opacity(0.65))
                                            .offset(y: -11)
                                    }
                                }
                                .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .position(x: min(max(x, 8), w - 8), y: barTop + 6)
                    }
                }
            }
            .frame(height: 46)
            HStack {
                Text("p.1").font(.caption2).foregroundStyle(BooksStyle.subInk)
                Spacer()
                Text("p.\(maxPage)").font(.caption2).foregroundStyle(BooksStyle.subInk)
            }
        }
    }
}
