import UIKit

// カメラが無いシミュレータでもOCR→自動配置を確認できるよう、
// サンプルページ本文を「本の写真」に見立てた画像に描く。

struct SamplePage {
    let pageNumber: Int
    let lines: [String]
}

enum Sample {
    static let pages: [SamplePage] = [
        SamplePage(pageNumber: 12, lines: [
            "第2章 プロセスとスレッド",
            "",
            "2.1 プロセスの概念",
            "プロセスとは、実行中のプログラムを抽象化した概念である。",
            "各プロセスには固有のアドレス空間が割り当てられ、他のプロセス",
            "から保護される。これによって、あるプロセスの誤りが他の",
            "プロセスへ波及することを防いでいる。",
            "",
            "オペレーティングシステムは、プロセスの生成・実行・終了を",
            "管理する責務を負う。プロセスの状態は一般に、実行中・実行可能・",
            "待機中の3つに大別される。",
            "",
            "2.2 コンテキストスイッチ",
            "CPUを別のプロセスへ切り替える操作をコンテキストスイッチと呼ぶ。",
            "このとき、レジスタやプログラムカウンタの値を保存・復元する",
            "必要があり、一定のオーバーヘッドが生じる。",
        ]),
        SamplePage(pageNumber: 13, lines: [
            "2.3 スレッド",
            "スレッドは、プロセス内で並行して実行される処理の単位である。",
            "同一プロセス内のスレッドはアドレス空間を共有するため、",
            "スレッド間の通信は低コストで行える。",
            "",
            "一方で、共有資源への同時アクセスは競合状態を引き起こす。",
            "これを防ぐために、ミューテックスやセマフォといった",
            "同期機構が用いられる。",
            "",
            "2.4 デッドロック",
            "デッドロックとは、複数のプロセスが互いに相手の資源の解放を",
            "待ち続け、処理が進まなくなる状態をいう。",
            "デッドロックの発生には4つの必要条件がある。",
        ]),
    ]

    static func render(_ page: SamplePage) -> UIImage {
        let width: CGFloat = 1000
        let margin: CGFloat = 70
        let lineHeight: CGFloat = 58
        let top: CGFloat = 90
        let bottom: CGFloat = 120
        let height = top + CGFloat(page.lines.count) * lineHeight + bottom

        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height))
        return renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: width, height: height))

            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 34),
                .foregroundColor: UIColor.black,
            ]
            for (i, line) in page.lines.enumerated() where !line.isEmpty {
                (line as NSString).draw(
                    at: CGPoint(x: margin, y: top + CGFloat(i) * lineHeight),
                    withAttributes: bodyAttrs)
            }

            let pn = String(page.pageNumber) as NSString
            let pnAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 30),
                .foregroundColor: UIColor.black,
            ]
            let size = pn.size(withAttributes: pnAttrs)
            pn.draw(
                at: CGPoint(x: (width - size.width) / 2, y: height - bottom + 30),
                withAttributes: pnAttrs)
        }
    }
}
