import SwiftUI

// パラパラモード: 付箋ページを順にめくる。剥がし完結（クイズ→ゴミ箱）を内部で処理する。

struct FlipView: View {
    let stickies: [Sticky]
    let bookTitle: String
    var onMastered: (Sticky) -> Void   // 覚えたが確定したとき（親が mastered フラグを立てる）
    var onClose: () -> Void

    @State private var index = 0

    // 剥がしフロー（fullScreenCover 内で完結させる）
    @State private var peelQuizSticky: Sticky?
    @State private var trashSticky: Sticky?
    @State private var undoTarget: Sticky?
    @State private var showUndo = false

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
                        Text("\(index + 1) / \(stickies.count) · \(bookTitle)")
                            .font(.footnote).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                    }
                }
                .padding(.horizontal, 18).padding(.top, 12)

                if stickies.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Text("🪶").font(.system(size: 40))
                        Text("まだ付箋がありません").foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                } else {
                    TabView(selection: $index) {
                        ForEach(Array(stickies.enumerated()), id: \.element.id) { i, s in
                            FlipCard(sticky: s, onPeelTapped: { peelQuizSticky = s }).tag(i)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                }
            }
            .overlay(alignment: .bottom) { undoToast }
        }
        .sheet(item: $peelQuizSticky) { sticky in
            PeelQuizView(
                sticky: sticky,
                onMastered: { peelQuizSticky = nil; trashSticky = sticky },
                onReturn:   { peelQuizSticky = nil }
            )
            .presentationDetents([.large])
        }
        .fullScreenCover(item: $trashSticky) { sticky in
            TrashGameView(
                sticky: sticky,
                onSuccess: { markMastered(sticky) },
                onDismiss: { trashSticky = nil; markMastered(sticky) }
            )
        }
        .animation(.spring(), value: showUndo)
    }

    private func markMastered(_ sticky: Sticky) {
        trashSticky = nil
        sticky.mastered = true
        sticky.masteredAt = .now
        onMastered(sticky)
        undoTarget = sticky
        withAnimation { showUndo = true }
        Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            await MainActor.run { withAnimation { showUndo = false } }
        }
    }

    @ViewBuilder private var undoToast: some View {
        if showUndo, let s = undoTarget {
            HStack(spacing: 12) {
                Text("付箋を剥がしました")
                Spacer()
                Button("元に戻す") {
                    s.mastered = false; s.masteredAt = nil
                    withAnimation { showUndo = false }
                }
                .bold()
            }
            .font(.subheadline)
            .padding(.horizontal, 18).padding(.vertical, 14)
            .background(.black.opacity(0.88))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16).padding(.bottom, 20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

private struct FlipCard: View {
    let sticky: Sticky
    var onPeelTapped: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("p.\(sticky.pageNumber)")
                    .font(.subheadline).bold().foregroundStyle(.white.opacity(0.6))

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(sticky.clipBefore, id: \.self) {
                        Text($0).foregroundStyle(.white.opacity(0.75))
                    }
                    Text(sticky.marker).bold().foregroundStyle(.white)
                        .padding(.bottom, 3)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(sticky.color.color).frame(height: 3)
                        }
                    ForEach(sticky.clipAfter, id: \.self) {
                        Text($0).foregroundStyle(.white.opacity(0.75))
                    }
                }
                .font(.body).lineSpacing(6)

                HStack(spacing: 10) {
                    Circle().fill(sticky.color.color).frame(width: 14, height: 14)
                    Text(sticky.heading).font(.title3).bold().foregroundStyle(.white)
                }
                .padding(.top, 8)

                if !sticky.memo.isEmpty {
                    Text(sticky.memo)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    onPeelTapped()
                } label: {
                    Label("覚えた・剥がす", systemImage: "hand.draw")
                        .font(.subheadline).bold()
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(sticky.color.color.opacity(0.25))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .stroke(sticky.color.color.opacity(0.6), lineWidth: 1))
                }
                .padding(.top, 4)
            }
            .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
        .peelable { onPeelTapped() }
    }
}
