import SwiftUI
import AudioToolbox

// パラパラモード: 付箋ページを順にめくる。

struct FlipView: View {
    let stickies: [Sticky]
    let bookTitle: String
    var onMastered: (Sticky) -> Void
    var onClose: () -> Void

    @State private var index = 0
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
                            FlipCard(sticky: s, onMastered: { markMastered(s) }).tag(i)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                    .padding(.bottom, 8)
                }
            }
            .overlay(alignment: .bottom) { undoToast }
        }
        .animation(.spring(), value: showUndo)
    }

    private func markMastered(_ sticky: Sticky) {
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
                Text("覚えました")
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
    var onMastered: () -> Void
    @Environment(VaultManager.self) private var vault

    @State private var dragOffset: CGSize = .zero
    @State private var isDismissing = false
    private let impactHaptic = UIImpactFeedbackGenerator(style: .rigid)
    private let successHaptic = UINotificationFeedbackGenerator()

    private var displayMemo: String {
        if let data = sticky.encryptedMemo { return vault.decrypt(data) ?? "" }
        return sticky.memo
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("p.\(sticky.pageNumber)")
                    .font(.subheadline).bold().foregroundStyle(BooksStyle.subInk)

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


            }
            .padding(.horizontal, 28).padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .offset(y: isDismissing ? -1000 : dragOffset.height)
        .opacity(isDismissing ? 0 : max(0, 1 + dragOffset.height / 400))
        .gesture(
            DragGesture(minimumDistance: 15)
                .onChanged { v in
                    guard !isDismissing, v.translation.height < 0 else { return }
                    dragOffset = v.translation
                }
                .onEnded { v in
                    guard !isDismissing else { return }
                    if v.translation.height < -80 {
                        peel()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            dragOffset = .zero
                        }
                    }
                }
        )
        .onAppear { impactHaptic.prepare(); successHaptic.prepare() }
    }

    private func peel() {
        impactHaptic.impactOccurred(intensity: 1.0)
        successHaptic.notificationOccurred(.success)
        AudioServicesPlaySystemSound(1103) // Tock
        withAnimation(.easeIn(duration: 0.28)) {
            isDismissing = true
            dragOffset = CGSize(width: 24, height: -1000)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            NotificationScheduler.cancel(stickyID: sticky.id)
            onMastered()
        }
    }
}
