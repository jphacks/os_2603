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
            BooksStyle.background.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    BooksCloseButton { onClose() }
                    Spacer()
                    if !stickies.isEmpty {
                        Text("\(index + 1) / \(stickies.count) · \(bookTitle)")
                            .font(.footnote).foregroundStyle(BooksStyle.subInk).lineLimit(1)
                    }
                }
                .padding(.horizontal, 18).padding(.top, 12)

                if stickies.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Text("🪶").font(.system(size: 40))
                        Text("まだ付箋がありません").foregroundStyle(BooksStyle.subInk)
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
                    .padding(.bottom, 8)
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
    @Environment(VaultManager.self) private var vault

    private var displayMemo: String {
        if let data = sticky.encryptedMemo { return vault.decrypt(data) ?? "" }
        return sticky.memo
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("p.\(sticky.pageNumber)")
                    .font(.subheadline).bold().foregroundStyle(BooksStyle.subInk)

                // 本のページのように、周りの文と付箋の行を明朝体で組む
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(sticky.clipBefore, id: \.self) {
                        Text($0).foregroundStyle(BooksStyle.subInk)
                    }
                    Text(sticky.marker).foregroundStyle(BooksStyle.ink)
                        .padding(.horizontal, 2)
                        .background(sticky.color.color.opacity(0.4))
                    ForEach(sticky.clipAfter, id: \.self) {
                        Text($0).foregroundStyle(BooksStyle.subInk)
                    }
                }
                .font(BooksStyle.serif(.title3)).lineSpacing(8)

                HStack(spacing: 10) {
                    Circle().fill(sticky.color.color).frame(width: 12, height: 12)
                    Text(sticky.heading).font(.title3).bold().foregroundStyle(BooksStyle.ink)
                }
                .padding(.top, 6)

                if !displayMemo.isEmpty {
                    Text(displayMemo)
                        .foregroundStyle(BooksStyle.ink)
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(BooksStyle.card)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button {
                    onPeelTapped()
                } label: {
                    Label("覚えた・剥がす", systemImage: "hand.draw")
                        .font(.subheadline).bold()
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(BooksStyle.ink)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 28).padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .peelable { onPeelTapped() }
    }
}
