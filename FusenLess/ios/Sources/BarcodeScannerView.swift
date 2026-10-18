import SwiftUI
import VisionKit

// ISBNバーコードの読み取り（VisionKit の DataScanner）。
// EAN-13（ISBNは978/979始まり）を対象にする。
@available(iOS 16.0, *)
struct BarcodeScannerView: UIViewControllerRepresentable {
    var onFound: (String) -> Void

    static var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
            qualityLevel: .accurate,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        try? controller.startScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onFound: (String) -> Void
        private var done = false
        init(onFound: @escaping (String) -> Void) { self.onFound = onFound }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) { handle(addedItems) }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didTapOn item: RecognizedItem) { handle([item]) }

        private func handle(_ items: [RecognizedItem]) {
            guard !done else { return }
            for item in items {
                if case let .barcode(barcode) = item,
                   let payload = barcode.payloadStringValue {
                    done = true
                    onFound(payload)
                    return
                }
            }
        }
    }
}

// バーコード読み取りシート（キャンセル付き・非対応時はメッセージ）。
struct BarcodeScanSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onFound: (String) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if #available(iOS 16.0, *), BarcodeScannerView.isSupported {
                    BarcodeScannerView { code in
                        onFound(code)
                        dismiss()
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .overlay(alignment: .top) {
                        Text("本の裏のISBNバーコードを枠に入れてください")
                            .font(.footnote).padding(10)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.top, 8)
                    }
                } else {
                    ContentUnavailableView(
                        "この端末ではバーコードを読み取れません",
                        systemImage: "barcode.viewfinder",
                        description: Text("シミュレータでは利用できません。実機でお試しください（ISBNは手入力もできます）"))
                }
            }
            .navigationTitle("ISBNを読み取る")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
    }
}

// ISBN から書名・著者を補完（openBD・ベストエフォート）。失敗しても手入力でOK。
enum BookLookup {
    struct Info { let title: String?; let author: String? }

    static func fetch(isbn: String) async -> Info? {
        let digits = isbn.filter { $0.isNumber }
        guard digits.count == 10 || digits.count == 13,
              let url = URL(string: "https://api.openbd.jp/v1/get?isbn=\(digits)") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let first = root.first as? [String: Any],
              let summary = first["summary"] as? [String: Any] else { return nil }
        let title = (summary["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let author = (summary["author"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return Info(title: title, author: author)
    }
}
