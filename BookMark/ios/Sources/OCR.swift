import Vision
import UIKit

// 端末内OCR（Apple Vision・日本語）。Web版のTesseractに相当するが高精度。
// 行の文字と位置（正規化・左上原点）を返す。

struct OCRLine: Identifiable {
    let id = UUID()
    let text: String
    let rect: CGRect   // 正規化座標・左上原点（表示画像にそのまま重ねられる）
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
        regionOfInterest roi: CGRect? = nil
    ) async -> OCRResult {
        guard let cg = image.cgImage else {
            return OCRResult(lines: [], pageNumber: nil)
        }
        guard !Task.isCancelled else { return OCRResult(lines: [], pageNumber: nil) }
        let orientation = cgOrientation(image.imageOrientation)

        let request = VNRecognizeTextRequest()
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                request.recognitionLanguages = ["ja-JP", "en-US"]
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
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
                            guard let text = observation.topCandidates(1).first?.string else { return nil }
                            let box = observation.boundingBox
                            return OCRLine(text: text, rect: CGRect(
                                x: box.minX, y: 1 - box.maxY,
                                width: box.width, height: box.height))
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

    // ページ番号推定（数字だけの行で、上下の余白に近いものを優先）。
    static func detectPageNumber(_ lines: [OCRLine]) -> Int? {
        let candidates = lines.filter {
            let t = $0.text.trimmingCharacters(in: .whitespaces)
            return t.range(of: "^[0-9]{1,4}$", options: .regularExpression) != nil
        }
        guard !candidates.isEmpty else { return nil }
        func score(_ l: OCRLine) -> Int {
            let top = l.rect.minY < 0.12 ? 1 : 0
            let bottom = l.rect.maxY > 0.88 ? 2 : 0
            return top + bottom
        }
        let best = candidates.max { score($0) < score($1) }!
        guard score(best) > 0 else { return nil }
        return Int(best.text.trimmingCharacters(in: .whitespaces))
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
