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

    // 確定できた番号は自動適用する。不確かな候補で別ページのピンを出さない。
    var preferredNumber: Int? { number }
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
struct SavedPagePin {
    let id: UUID
    let pageNumber: Int
    let rect: CGRect?
}

enum PinRestoration {
    // ページが判明してから、そのページの保存座標だけを取り出す。本文OCRには依存しない。
    static func pins(on pageNumber: Int?, from notes: [SavedPagePin]) -> [UUID: CGRect] {
        guard let pageNumber, pageNumber > 0 else { return [:] }
        var result: [UUID: CGRect] = [:]
        for note in notes where note.pageNumber == pageNumber {
            if let rect = normalized(note.rect) { result[note.id] = rect }
        }
        return result
    }

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
        // 下側の数字だけで確定せず、上側のノンブルとも比較する。
        for region in regions {
            guard !Task.isCancelled else { return PageNumberReading(number: nil, candidates: []) }
            let result = await OCR.recognize(image, regionOfInterest: region, pageNumbersOnly: true)
            observations += result.lines.map {
                PageNumberObservation(text: $0.text, rect: $0.rect, confidence: $0.confidence)
            }
        }
        let initial = PageNumberResolver.resolve(observations)
        if initial.number != nil { return initial }

        // 広い帯のままでは小さい文字が潰れるため、左右・中央の重なる領域を独立して拡大。
        // 元画像の座標へ戻して判定し、本文内の数字は引き続き除外する。
        for region in regions {
            for x: CGFloat in [0, 0.3, 0.6] {
                guard !Task.isCancelled else { return PageNumberReading(number: nil, candidates: []) }
                let tile = CGRect(x: x, y: region.minY, width: 0.4, height: region.height)
                guard let enhanced = enhancedMargin(image, region: tile) else { continue }
                let result = await OCR.recognize(enhanced, pageNumbersOnly: true)
                observations += result.lines.map {
                    PageNumberObservation(text: $0.text,
                        rect: CGRect(x: tile.minX + $0.rect.minX * tile.width,
                                     y: tile.minY + $0.rect.minY * tile.height,
                                     width: $0.rect.width * tile.width, height: $0.rect.height * tile.height),
                        confidence: $0.confidence)
                }
            }
        }
        let reading = PageNumberResolver.resolve(observations)
        if reading.number != nil || !reading.candidates.isEmpty { return reading }

        // 白抜きの装飾ノンブル用。ページの縁や本文と結合しないよう、
        // 上下端から少し内側の小領域で局所的な明るさの差を取り出す。
        // 通常OCRで候補がある場合はこの強い補正で上書きしない。
        for y: CGFloat in [0.89, 0.01] {
            for x: CGFloat in [0, 0.2, 0.4, 0.6, 0.8] {
                guard !Task.isCancelled else { return PageNumberReading(number: nil, candidates: []) }
                let tile = CGRect(x: x, y: y, width: 0.2, height: 0.1)
                guard let prepared = lightDigits(image, region: tile) else { continue }
                let result = await OCR.recognize(prepared, pageNumbersOnly: true, latinDigitsOnly: true)
                observations += result.lines.compactMap { line in
                    // 背景ノイズから生成される短い数字や補正文字は採用しない。
                    guard let parsed = PageNumberResolver.parse(line.text), !parsed.corrected,
                          parsed.value >= 10, line.confidence >= 0.8 else { return nil }
                    return PageNumberObservation(text: line.text,
                        rect: CGRect(x: tile.minX + line.rect.minX * tile.width,
                                     y: tile.minY + line.rect.minY * tile.height,
                                     width: line.rect.width * tile.width, height: line.rect.height * tile.height),
                        confidence: line.confidence)
                }
            }
        }
        return PageNumberResolver.resolve(observations)
    }

    // 周囲より明るい画素を黒文字へ変換。単純な反転で残る丸い背景を抑える。
    private static func lightDigits(_ image: UIImage, region: CGRect) -> UIImage? {
        guard image.imageOrientation == .up, let cg = image.cgImage,
              let patch = cg.cropping(to: CGRect(x: region.minX * CGFloat(cg.width),
                  y: region.minY * CGFloat(cg.height), width: region.width * CGFloat(cg.width),
                  height: region.height * CGFloat(cg.height))) else { return nil }
        let w = patch.width, h = patch.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(patch, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        var values = [Double](repeating: 0, count: w * h)
        var sums = [Double](repeating: 0, count: (w + 1) * (h + 1))
        for y in 0..<h { for x in 0..<w {
            let i = y * w + x
            values[i] = (Double(bytes[i*4]) + Double(bytes[i*4+1]) + Double(bytes[i*4+2])) / 765
            sums[(y+1)*(w+1)+x+1] = values[i] + sums[y*(w+1)+x+1]
                + sums[(y+1)*(w+1)+x] - sums[y*(w+1)+x]
        }}
        let radius = max(2, Int((CGFloat(cg.width) / 280).rounded()))
        for y in 0..<h { for x in 0..<w {
            let x0 = max(0, x-radius), x1 = min(w, x+radius+1)
            let y0 = max(0, y-radius), y1 = min(h, y+radius+1)
            let mean = (sums[y1*(w+1)+x1] - sums[y0*(w+1)+x1]
                - sums[y1*(w+1)+x0] + sums[y0*(w+1)+x0]) / Double((x1-x0)*(y1-y0))
            let i = y*w+x
            let value: UInt8 = values[i] > mean + 0.04 ? 0 : 255
            bytes[i*4] = value; bytes[i*4+1] = value; bytes[i*4+2] = value; bytes[i*4+3] = 255
        }}
        let output = bytes.withUnsafeMutableBytes { buffer -> CGImage? in
            let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w*4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            return context?.makeImage()
        }
        guard let output else { return nil }
        let scale = max(1, min(4, 900 / CGFloat(w)))
        let enlarged = CIImage(cgImage: output).applyingFilter("CILanczosScaleTransform",
            parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1])
        guard let final = imageContext.createCGImage(enlarged, from: enlarged.extent) else { return nil }
        return UIImage(cgImage: final)
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
