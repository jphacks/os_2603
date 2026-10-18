import SwiftUI

// 本の付箋を Markdown にして ShareLink で外部アプリに渡す。

struct ExportButton: View {
    let book: Book

    private var markdown: String {
        makeMarkdown(book: book)
    }

    var body: some View {
        ShareLink(
            item: markdown,
            subject: Text(book.title),
            message: Text("FusenLess から書き出し"),
            preview: SharePreview(
                "\(book.title) — 付箋 \(activeStickyCount)枚",
                image: Image(systemName: "doc.plaintext")
            )
        ) {
            Label("書き出す", systemImage: "square.and.arrow.up")
        }
    }

    private var activeStickyCount: Int {
        book.stickies.filter { $0.placed && !$0.mastered }.count
    }
}

// MARK: - Markdown 生成

private func makeMarkdown(book: Book) -> String {
    let placed = book.stickies
        .filter { $0.placed }
        .sorted { ($0.pageNumber, $0.order) < ($1.pageNumber, $1.order) }

    var lines: [String] = []

    lines.append("# \(book.title)")
    if let author = book.author { lines.append("著者: \(author)") }
    lines.append("書き出し: \(formatted(Date.now))")
    lines.append("")
    lines.append("---")
    lines.append("")

    var lastPage: Int? = nil
    for s in placed {
        if s.pageNumber != lastPage {
            lines.append("## p.\(s.pageNumber)")
            lines.append("")
            lastPage = s.pageNumber
        }

        lines.append("### \(s.heading)\(s.mastered ? " ✓" : "")")
        lines.append("")

        if !s.clipBefore.isEmpty {
            for c in s.clipBefore {
                lines.append("> \(c)")
            }
        }

        lines.append("**\(s.marker)**")

        if !s.clipAfter.isEmpty {
            for c in s.clipAfter {
                lines.append("> \(c)")
            }
        }

        lines.append("")

        if !s.memo.isEmpty {
            lines.append("📝 \(s.memo)")
            lines.append("")
        }

        let stars = String(repeating: "★", count: s.importance)
            + String(repeating: "☆", count: 3 - s.importance)
        lines.append("重要度: \(stars)")
        lines.append("")
        lines.append("---")
        lines.append("")
    }

    if placed.isEmpty {
        lines.append("（付箋がまだありません）")
    }

    return lines.joined(separator: "\n")
}

private func formatted(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateStyle = .short
    f.timeStyle = .short
    f.locale = Locale(identifier: "ja_JP")
    return f.string(from: date)
}
