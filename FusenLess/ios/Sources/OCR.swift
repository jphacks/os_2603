@preconcurrency import Vision
import UIKit

// 端末内OCR（Apple Vision・日本語）。Web版のTesseractに相当するが高精度。
// 行の文字と位置（正規化・左上原点）を返す。

struct OCRLine: Identifiable {
    let id = UUID()
    let text: String
    let rect: CGRect   // 正規化座標・左上原点（表示画像にそのまま重ねられる）
    var confidence: Float = 1
}

struct OCRResult {
    let lines: [OCRLine]
    let pageNumber: Int?
}

enum OCR {
    /// `regionOfInterest` は左上原点の正規化矩形。指定するとその範囲だけOCRする
    /// （プライバシー・速度のため、ページ全体は原則読まない）。
    static func recognize(
        _ image: UIImage,
        regionOfInterest roi: CGRect? = nil,
        pageNumbersOnly: Bool = false,
        latinDigitsOnly: Bool = false
    ) async -> OCRResult {
        guard let cg = image.cgImage else {
            return OCRResult(lines: [], pageNumber: nil)
        }
        guard !Task.isCancelled else { return OCRResult(lines: [], pageNumber: nil) }
        let orientation = cgOrientation(image.imageOrientation)

        let request = VNRecognizeTextRequest()
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                request.recognitionLanguages = latinDigitsOnly ? ["en-US"] : ["ja-JP", "en-US"]
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = !pageNumbersOnly
                if pageNumbersOnly { request.minimumTextHeight = 0.002 }
                if let roi {
                    // Vision は左下原点なので上下を反転。[0,1]にクランプ。
                    let y = max(0, min(1, 1 - roi.maxY))
                    let h = max(0, min(1 - y, roi.height))
                    let x = max(0, min(1, roi.minX))
                    let w = max(0, min(1 - x, roi.width))
                    request.regionOfInterest = CGRect(x: x, y: y, width: w, height: h)
                }

                let handler = VNImageRequestHandler(
                    cgImage: cg, orientation: orientation, options: [:])
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try handler.perform([request])
                        let lines = (request.results ?? []).compactMap { observation -> OCRLine? in
                            guard let candidate = observation.topCandidates(1).first else { return nil }
                            let text = candidate.string
                            let box = observation.boundingBox
                            return OCRLine(text: text, rect: OCRGeometry.imageRect(
                                from: box, regionOfInterest: request.regionOfInterest), confidence: candidate.confidence)
                        }.sorted { $0.rect.minY < $1.rect.minY }
                        continuation.resume(returning: OCRResult(
                            lines: lines, pageNumber: detectPageNumber(lines)))
                    } catch {
                        // perform 自体が失敗した場合も必ず待機を終了する。
                        continuation.resume(returning: OCRResult(lines: [], pageNumber: nil))
                    }
                }
            }
        }, onCancel: {
            request.cancel()
        })
    }

    // 汎用OCRのページ候補も同じ判定器を使う。画面の自動入力は専用Readerに一本化。
    static func detectPageNumber(_ lines: [OCRLine]) -> Int? {
        PageNumberResolver.resolve(lines.map {
            PageNumberObservation(text: $0.text, rect: $0.rect, confidence: $0.confidence)
        }).number
    }

    private static func cgOrientation(
        _ o: UIImage.Orientation
    ) -> CGImagePropertyOrientation {
        switch o {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

// 認識済みの行から付箋を作る処理。UI と切り離し、全体・範囲 OCR で共用する。
struct OCRSelection {
    let marker: String
    let before: [String]
    let after: [String]

    static func expandedRegion(for rect: CGRect) -> CGRect {
        let pad = max(0.03, rect.height * 0.9)
        return rect.insetBy(dx: -0.02, dy: -pad)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    static func extract(from lines: [OCRLine], in rect: CGRect,
                        requireWholeLines: Bool = false) -> OCRSelection? {
        let region = expandedRegion(for: rect)
        let nearby = lines.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            $0.rect.maxX > rect.minX && $0.rect.minX < rect.maxX &&
            $0.rect.midY >= region.minY && $0.rect.midY <= region.maxY
        }.sorted { $0.rect.minY < $1.rect.minY }
        let selected = nearby.filter { $0.rect.midY >= rect.minY && $0.rect.midY <= rect.maxY }
        guard !selected.isEmpty else { return nil }
        // 行の一部だけを囲んだ場合は、全体OCRの行全文を保存せず範囲OCRへ戻す。
        if requireWholeLines && selected.contains(where: {
            $0.rect.minX < region.minX || $0.rect.maxX > region.maxX
        }) { return nil }
        return OCRSelection(
            marker: selected.map { $0.text }.joined(),
            before: Array(nearby.filter { $0.rect.midY < rect.minY }.suffix(2).map { $0.text }),
            after: Array(nearby.filter { $0.rect.midY > rect.maxY }.prefix(2).map { $0.text }))
    }
}

// Vision の ROI 内・左下原点の座標を、元画像全体・左上原点へ変換する。
// 全体OCRでは ROI=(0,0,1,1) なので従来の上下反転と同じ結果になる。
enum OCRGeometry {
    static func imageRect(from box: CGRect, regionOfInterest roi: CGRect) -> CGRect {
        CGRect(x: roi.minX + box.minX * roi.width,
               y: 1 - (roi.minY + box.maxY * roi.height),
               width: box.width * roi.width,
               height: box.height * roi.height)
    }
}
