import SwiftUI
import SwiftData

// 覚えた（剥がした）付箋の一覧。元に戻すことができる。

struct MasteredView: View {
    @Bindable var book: Book
    @Environment(\.dismiss) private var dismiss

    private var mastered: [Sticky] {
        book.stickies
            .filter { $0.mastered }
            .sorted { ($0.masteredAt ?? $0.createdAt) > ($1.masteredAt ?? $1.createdAt) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if mastered.isEmpty {
                    ContentUnavailableView(
                        "覚えた付箋はまだありません",
                        systemImage: "checkmark.circle",
                        description: Text("付箋を剥がすと「覚えた」としてここに残ります"))
                } else {
                    List {
                        ForEach(mastered) { s in
                            MasteredRow(sticky: s)
                        }
                    }
                }
            }
            .navigationTitle("覚えた付箋")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}

private struct MasteredRow: View {
    @Bindable var sticky: Sticky

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(sticky.color.color)
                .frame(width: 5)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(sticky.heading).font(.headline).lineLimit(1)
                    Text("p.\(sticky.pageNumber)")
                        .font(.caption2).bold().foregroundStyle(.secondary)
                }
                Text(sticky.marker).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let at = sticky.masteredAt {
                    Text("覚えた: \(at.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button("元に戻す") {
                sticky.mastered = false
                sticky.masteredAt = nil
            }
            .font(.caption).foregroundStyle(.blue)
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}
