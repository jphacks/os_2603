import SwiftUI

// 紙の本のような、生成り色の落ち着いた見た目。
enum Theme {
    static let background = Color(red: 0.965, green: 0.945, blue: 0.906)
    static let card = Color(red: 0.992, green: 0.984, blue: 0.965)
    static let ink = Color(red: 0.16, green: 0.17, blue: 0.20)
    static let subInk = Color(red: 0.47, green: 0.46, blue: 0.45)
    static let accent = Color(red: 0.85, green: 0.62, blue: 0.22)
    static let edge = Color(red: 0.84, green: 0.78, blue: 0.68)

    static func serif(_ style: Font.TextStyle) -> Font {
        .system(style, design: .serif)
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd"
        return f
    }()
}

/// 画面の切り替えを親から操作するための状態（本の画面 → ホームで撮る など）
@Observable
final class AppState {
    enum Tab: Hashable { case home, books, settings }
    var tab: Tab = .home
}

struct CaptureButton: ButtonStyle {
    var ghost = false
    func makeBody(configuration: Configuration) -> some View {
        CaptureButtonBody(configuration: configuration, ghost: ghost)
    }
}

private struct CaptureButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let ghost: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.subheadline).bold()
            .padding(.vertical, 14)
            .foregroundStyle(ghost ? Theme.ink : .white)
            .background(ghost ? Theme.card : Theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(Color.black.opacity(ghost ? 0.08 : 0)))
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.85 : 1)
    }
}
