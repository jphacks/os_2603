import SwiftUI
import VisionKit

// ISBN から書誌情報（書名・著者・出版社・紹介・表紙）を取得する。
// 送るのは ISBN だけで、本文や画像は送らない。
// openBD → 足りない分を Google Books（キーなしは回数制限あり）→ 表紙は版元ドットコムで補う。

struct BookInfo {
    var title: String
    var author: String?
    var publisher: String?
    var publishedDate: String?
    var summary: String?
    var pageCount: Int?
    var coverURL: URL?
}

enum BookInfoService {
    static func lookup(isbn: String) async -> BookInfo? {
        let openBD = await lookupOpenBD(isbn: isbn)
        let needsMore = openBD == nil || openBD?.summary == nil || openBD?.coverURL == nil || openBD?.pageCount == nil
        let google = needsMore ? await lookupGoogleBooks(isbn: isbn) : nil

        guard var info = openBD ?? google else { return nil }
        if let google {
            info.author = info.author ?? google.author
            info.publisher = info.publisher ?? google.publisher
            info.publishedDate = info.publishedDate ?? google.publishedDate
            info.summary = info.summary ?? google.summary
            info.pageCount = info.pageCount ?? google.pageCount
            info.coverURL = info.coverURL ?? google.coverURL
        }
        // openBD に表紙がないことが多いので、版元ドットコムの書影を使う（無い本は 404）
        info.coverURL = info.coverURL ?? URL(string: "https://www.hanmoto.com/bd/img/\(isbn).jpg")
        return info
    }

    static func fetchCover(_ url: URL?) async -> Data? {
        guard let url,
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              UIImage(data: data) != nil
        else { return nil }
        return data
    }

    /// 978/979 で始まる 13 桁で、チェックディジットが正しいか
    static func isValidISBN13(_ code: String) -> Bool {
        let digits = code.compactMap(\.wholeNumberValue)
        guard digits.count == 13, code.count == 13,
              code.hasPrefix("978") || code.hasPrefix("979") else { return false }
        let sum = digits.prefix(12).enumerated()
            .reduce(0) { $0 + $1.element * ($1.offset.isMultiple(of: 2) ? 1 : 3) }
        return (10 - sum % 10) % 10 == digits[12]
    }

    // MARK: - openBD

    private static func lookupOpenBD(isbn: String) async -> BookInfo? {
        guard let url = URL(string: "https://api.openbd.jp/v1/get?isbn=\(isbn)"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let record = array.first as? [String: Any],
              let summary = record["summary"] as? [String: Any],
              let title = nonEmpty(summary["title"] as? String)
        else { return nil }

        let onix = record["onix"] as? [String: Any]
        let collateral = onix?["CollateralDetail"] as? [String: Any]
        let texts = collateral?["TextContent"] as? [[String: Any]] ?? []
        // 03: 内容紹介（長い）、02: 短い紹介
        let description = ["03", "02"].lazy.compactMap { type in
            texts.first { $0["TextType"] as? String == type }?["Text"] as? String
        }.first

        let descriptive = onix?["DescriptiveDetail"] as? [String: Any]
        let extents = descriptive?["Extent"] as? [[String: Any]] ?? []
        let pages = extents.lazy.compactMap { ($0["ExtentValue"] as? String).flatMap { Int($0) } }.first

        return BookInfo(
            title: title,
            author: nonEmpty((summary["author"] as? String).map(cleanAuthor)),
            publisher: nonEmpty(summary["publisher"] as? String),
            publishedDate: nonEmpty((summary["pubdate"] as? String).map(formatPubdate)),
            summary: nonEmpty(description),
            pageCount: pages,
            coverURL: nonEmpty(summary["cover"] as? String).flatMap(URL.init(string:))
        )
    }

    /// 「山田太郎／著 鈴木花子／訳」→「山田太郎 著・鈴木花子 訳」
    private static func cleanAuthor(_ raw: String) -> String {
        raw.split(separator: " ")
            .map { $0.replacingOccurrences(of: "／", with: " ") }
            .joined(separator: "・")
    }

    /// 「20200115」→「2020.01.15」、「2020-01」→「2020.01」
    private static func formatPubdate(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        switch digits.count {
        case 8: return "\(digits.prefix(4)).\(digits.dropFirst(4).prefix(2)).\(digits.suffix(2))"
        case 6: return "\(digits.prefix(4)).\(digits.suffix(2))"
        default: return raw
        }
    }

    // MARK: - Google Books

    private static func lookupGoogleBooks(isbn: String) async -> BookInfo? {
        guard let url = URL(string: "https://www.googleapis.com/books/v1/volumes?q=isbn:\(isbn)"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]],
              let volume = items.first?["volumeInfo"] as? [String: Any],
              let title = nonEmpty(volume["title"] as? String)
        else { return nil }

        let images = volume["imageLinks"] as? [String: Any]
        let thumbnail = (images?["thumbnail"] as? String ?? images?["smallThumbnail"] as? String)?
            .replacingOccurrences(of: "http://", with: "https://")

        return BookInfo(
            title: title,
            author: nonEmpty((volume["authors"] as? [String])?.joined(separator: "・")),
            publisher: nonEmpty(volume["publisher"] as? String),
            publishedDate: nonEmpty((volume["publishedDate"] as? String).map(formatPubdate)),
            summary: nonEmpty(volume["description"] as? String),
            pageCount: volume["pageCount"] as? Int,
            coverURL: thumbnail.flatMap(URL.init(string:))
        )
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}

// MARK: - ISBN バーコード読み取り（VisionKit）

struct ISBNScannerView: UIViewControllerRepresentable {
    var onFound: (String) -> Void

    @MainActor static var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13])],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onFound: (String) -> Void
        private var done = false

        init(onFound: @escaping (String) -> Void) { self.onFound = onFound }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in allItems {
                // 本には2段のバーコードがある。下段（192…の価格コード）は無視する
                guard case .barcode(let barcode) = item,
                      let code = barcode.payloadStringValue,
                      BookInfoService.isValidISBN13(code) else { continue }
                done = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onFound(code)
                return
            }
        }
    }
}
