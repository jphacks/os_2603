import SwiftUI
import UIKit
import CoreImage

// Apple Books のような、白地に黒い文字・太い見出し・表紙を大きく見せる見た目。
// 本文の引用（付箋を貼った行）だけ明朝体にして「本の文字」らしくする。
enum Theme {
    static let background = Color.white
    static let card = Color(red: 0.965, green: 0.965, blue: 0.972)   // 薄いグレーのカード
    static let ink = Color(red: 0.08, green: 0.08, blue: 0.09)
    static let subInk = Color(red: 0.52, green: 0.52, blue: 0.55)
    static let accent = Color(red: 0.08, green: 0.08, blue: 0.09)    // 黒いボタン・選択中のタブ
    static let ring = Color(red: 0.0, green: 0.55, blue: 0.95)       // 目標リングの青
    static let separator = Color.black.opacity(0.08)
    static let edge = Color(red: 0.86, green: 0.84, blue: 0.80)

    /// 本の文字（引用・パラパラ）用の明朝体
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

/// 黒いカプセルのボタン（ghost は薄いグレー）
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
            .padding(.vertical, 13)
            .padding(.horizontal, 16)
            .foregroundStyle(ghost ? Theme.ink : .white)
            .background(ghost ? Theme.card : Theme.accent, in: Capsule())
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.8 : 1)
    }
}

/// 見出しと右矢印（「今年読んだブック ＞」のような行）
struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.title3.bold()).foregroundStyle(Theme.ink)
            if let subtitle {
                Text(subtitle).font(.footnote).foregroundStyle(Theme.subInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 表紙の平均色（本の画面の背景に使う）
enum CoverColor {
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])
    private static var cache: [Int: UIColor] = [:]

    static func average(of data: Data?) -> UIColor? {
        guard let data else { return nil }
        if let hit = cache[data.hashValue] { return hit }
        guard let image = CIImage(data: data) else { return nil }
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image,
            kCIInputExtentKey: CIVector(cgRect: image.extent),
        ])
        guard let output = filter?.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        let color = UIColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                            blue: CGFloat(pixel[2]) / 255, alpha: 1)
        cache[data.hashValue] = color
        return color
    }
}

extension UIColor {
    /// 白い文字が読めるよう、暗めにした色
    func darkened(_ amount: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: min(s, 0.55), brightness: min(b, 1 - amount), alpha: a)
    }
}
