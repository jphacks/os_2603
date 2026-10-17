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
        let orientation = cgOrientation(image.imageOrientation)

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations =
                    (request.results as? [VNRecognizedTextObservation]) ?? []
                var lines: [OCRLine] = []
                for obs in observations {
                    guard let top = obs.topCandidates(1).first else { continue }
                    let bb = obs.boundingBox  // 正規化・左下原点
                    let rect = CGRect(
                        x: bb.minX, y: 1 - bb.maxY,
                        width: bb.width, height: bb.height)
                    lines.append(OCRLine(text: top.string, rect: rect))
                }
                lines.sort { $0.rect.minY < $1.rect.minY }
                continuation.resume(
                    returning: OCRResult(
                        lines: lines, pageNumber: detectPageNumber(lines)))
            }
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
                try? handler.perform([request])
            }
        }
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
