import Foundation
import CoreGraphics

struct PageNumberObservation {
    let text: String
    let rect: CGRect
    let confidence: Float
}

struct PageNumberReading {
    let number: Int?
    let candidates: [Int]
}

// 数字を全部抜き出すと「7.8」「第7章」までページになるため、許可した形式だけ読む。
enum PageNumberResolver {
    struct Parsed {
        let value: Int
        let corrected: Bool
        let labeled: Bool
    }

    static func parse(_ text: String) -> Parsed? {
        var value = text.precomposedStringWithCompatibilityMapping.lowercased()
            .components(separatedBy: .whitespacesAndNewlines).joined()
        let wrappers = CharacterSet(charactersIn: "-—–・·[](){}<>〈〉「」")
        value = value.trimmingCharacters(in: wrappers)
        var labeled = false
        for prefix in ["page", "p.", "p"] where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count); labeled = true; break
        }
        for suffix in ["ページ", "頁"] where value.hasSuffix(suffix) {
            value.removeLast(suffix.count); labeled = true; break
        }
        value = value.trimmingCharacters(in: wrappers)
        guard !value.isEmpty, value.count <= 4 else { return nil }
        let digits = CharacterSet(charactersIn: "0123456789")
        var corrected = false
        if value.unicodeScalars.contains(where: { !digits.contains($0) }) {
            let allowed = CharacterSet(charactersIn: "0123456789ilo")
            guard value.unicodeScalars.allSatisfy({ allowed.contains($0) }),
                  value.unicodeScalars.contains(where: { digits.contains($0) }) else { return nil }
            value = value.replacingOccurrences(of: "i", with: "1")
                .replacingOccurrences(of: "l", with: "1")
                .replacingOccurrences(of: "o", with: "0")
            corrected = true
        }
        guard let number = Int(value), number > 0 else { return nil }
        return Parsed(value: number, corrected: corrected, labeled: labeled)
    }

    static func resolve(_ observations: [PageNumberObservation]) -> PageNumberReading {
        var scores: [Int: Double] = [:]
        var counts: [Int: Int] = [:]
        for observation in observations {
            guard let parsed = parse(observation.text), observation.confidence >= 0.45,
                  observation.rect.width < 0.3, observation.rect.height < 0.09 else { continue }
            let y = observation.rect.midY
            // 上下の余白以外は、数字だけでもページ番号候補にしない。
            guard y < 0.22 || y > 0.78 else { continue }
            let edge = max(0, 1 - min(y, 1 - y) / 0.22)
            let score = 0.55 * Double(observation.confidence) + 0.3 * Double(edge)
                + (y > 0.78 ? 0.05 : 0) + (parsed.labeled ? 0.08 : 0)
                - (parsed.corrected ? 0.14 : 0)
                - (parsed.value < 10 && !parsed.labeled ? 0.12 : 0)
            scores[parsed.value] = max(scores[parsed.value] ?? 0, score)
            counts[parsed.value, default: 0] += 1
        }
        var ranked: [(number: Int, score: Double)] = []
        for (number, score) in scores {
            let agreement: Double = counts[number, default: 0] > 1 ? 0.04 : 0
            ranked.append((number: number, score: score + agreement))
        }
        ranked.sort {
            if $0.score == $1.score { return $0.number < $1.number }
            return $0.score > $1.score
        }
        let candidates = ranked.prefix(3).map { $0.number }
        guard let best = ranked.first, best.score >= 0.72,
              ranked.count == 1 || best.score - ranked[1].score >= 0.12 else {
            return PageNumberReading(number: nil, candidates: candidates)
        }
        return PageNumberReading(number: best.number, candidates: candidates)
    }
}

// 保存された場所を先に出す。自動照合で手動の位置を上書きしない。
enum PinRestoration {
    static func normalized(_ rect: CGRect?) -> CGRect? {
        guard let rect, [rect.minX, rect.minY, rect.width, rect.height].allSatisfy({ $0.isFinite }),
              rect.width > 0, rect.height > 0 else { return nil }
        let width = min(rect.width, 1), height = min(rect.height, 1)
        return CGRect(x: min(max(rect.minX, 0), 1 - width),
                      y: min(max(rect.minY, 0), 1 - height), width: width, height: height)
    }

    static func restore(saved: CGRect?, matched: CGRect?) -> CGRect? {
        normalized(saved) ?? normalized(matched)
    }
}

#if canImport(UIKit)
import UIKit
import CoreImage

// ページ番号専用。全体の本文OCRと独立してキャンセル・適用を管理する。
enum PageNumberReader {
    private static let imageContext = CIContext(options: [.cacheIntermediates: false])

    static func read(_ image: UIImage) async -> PageNumberReading {
        let regions = [CGRect(x: 0, y: 0.68, width: 1, height: 0.32),
                       CGRect(x: 0, y: 0, width: 1, height: 0.28)]
        var observations: [PageNumberObservation] = []
        for region in regions {
            guard !Task.isCancelled else { return PageNumberReading(number: nil, candidates: []) }
            let normal = await OCR.recognize(image, regionOfInterest: region, pageNumbersOnly: true)
            observations += normal.lines.map { PageNumberObservation(text: $0.text, rect: $0.rect, confidence: $0.confidence) }
            guard !Task.isCancelled else { return PageNumberReading(number: nil, candidates: []) }
            // 小さなノンブル用に、余白だけを拡大・コントラスト調整して再認識する。
            if let enhanced = enhancedMargin(image, region: region) {
                let result = await OCR.recognize(enhanced, pageNumbersOnly: true)
                observations += result.lines.map {
                    PageNumberObservation(text: $0.text,
                        rect: CGRect(x: region.minX + $0.rect.minX * region.width,
                                     y: region.minY + $0.rect.minY * region.height,
                                     width: $0.rect.width * region.width, height: $0.rect.height * region.height),
                        confidence: $0.confidence)
                }
            }
        }
        return PageNumberResolver.resolve(observations)
    }

    private static func enhancedMargin(_ image: UIImage, region: CGRect) -> UIImage? {
        guard image.imageOrientation == .up, let cg = image.cgImage else { return nil }
        let rect = CGRect(x: region.minX * CGFloat(cg.width), y: region.minY * CGFloat(cg.height),
                          width: region.width * CGFloat(cg.width), height: region.height * CGFloat(cg.height))
        guard let cropped = cg.cropping(to: rect) else { return nil }
        let scale = max(1, min(3, 1800 / CGFloat(cropped.width)))
        let adjusted = CIImage(cgImage: cropped)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0, kCIInputContrastKey: 1.25])
            .applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1])
        guard let output = imageContext.createCGImage(adjusted, from: adjusted.extent) else { return nil }
        return UIImage(cgImage: output)
    }
}
#endif
