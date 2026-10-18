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
                    .overlay { swipeHints }
                    .padding(.bottom, 8)
                }
            }
            .overlay(alignment: .bottom) { undoToast }
        }
        .animation(.spring(), value: showUndo)
    }

    /// めくれる方向だけに出す薄い矢印。タップでもその方向へめくれる。
    /// 矢印のまわり以外はタップを素通りさせ、スワイプや付箋の操作を邪魔しない。
    private var swipeHints: some View {
        HStack {
            hintArrow("chevron.compact.left", label: "前の付箋", enabled: index > 0) {
                index -= 1
            }
            Spacer()
            hintArrow("chevron.compact.right", label: "次の付箋",
                      enabled: index < stickies.count - 1) {
                index += 1
            }
        }
        .padding(.horizontal, 2)
        .animation(.easeInOut(duration: 0.2), value: index)
    }

    /// 縦長の矢印（文字の大きさではなく枠で縦横を決める）。押せる範囲は見た目より広くとる。
    private func hintArrow(_ name: String, label: String, enabled: Bool,
                           action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) { action() }
        } label: {
            Image(systemName: name)
                .resizable()
                .fontWeight(.light)
                .frame(width: 18, height: 72)
                .foregroundStyle(BooksStyle.subInk.opacity(0.35))
                .frame(width: 44, height: 110)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0)
        .disabled(!enabled)
        .accessibilityLabel(label)
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

                StickyNoteView(color: sticky.color.color,
                               heading: sticky.heading,
                               memo: displayMemo,
                               seed: sticky.id)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)

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

// 紙の付箋のように見せる（色紙・上のマスキングテープ・少しの傾き・影）。
private struct StickyNoteView: View {
    let color: Color
    let heading: String
    let memo: String
    let seed: UUID

    /// 本文はメモ。メモがなければ見出し。
    private var body_: String { memo.isEmpty ? heading : memo }
    /// 見出しがメモの書き出しと同じなら二重に出さない（AIの見出しなど違う時だけ下に添える）
    private var caption: String? {
        guard !memo.isEmpty, !heading.isEmpty else { return nil }
        let squashed = memo.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        return squashed.hasPrefix(heading) ? nil : heading
    }
    /// 付箋ごとに決まった小さな傾き（-2.5〜2.5度）
    private var tilt: Double {
        let v = seed.uuid.0 ^ seed.uuid.7 ^ seed.uuid.15
        return (Double(v) / 255 - 0.5) * 5
    }

    var body: some View {
        VStack(spacing: 14) {
            Text(body_)
                .font(.system(.title3, design: .rounded).weight(.medium))
                .foregroundStyle(BooksStyle.ink.opacity(0.85))
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
            if let caption {
                Text(caption)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(BooksStyle.ink.opacity(0.5))
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 34)
        .padding(.bottom, 28)
        .frame(maxWidth: 300, minHeight: 190)
        .background(
            ZStack {
                Color.white
                color.opacity(0.62)
                // 紙のわずかな陰影（下ほど少し濃い）
                LinearGradient(colors: [.white.opacity(0.18), .black.opacity(0.04)],
                               startPoint: .top, endPoint: .bottom)
            }
        )
        .shadow(color: .black.opacity(0.10), radius: 1, y: 1)
        .shadow(color: .black.opacity(0.12), radius: 8, x: 2, y: 6)
        .overlay(alignment: .top) {
            // マスキングテープ
            Rectangle()
                .fill(Color(red: 0.93, green: 0.88, blue: 0.70).opacity(0.75))
                .frame(width: 96, height: 24)
                .overlay(Rectangle().stroke(.white.opacity(0.35), lineWidth: 0.5))
                .rotationEffect(.degrees(-tilt * 0.6))
                .offset(y: -11)
                .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
        }
        .rotationEffect(.degrees(tilt))
        .accessibilityElement(children: .combine)
    }
}
