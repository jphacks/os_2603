"""Check ROI coordinate conversion; optionally verify OCR on a local image.
Usage: python3 Tests/check_ocr_region.py [path/to/IMG_6494.PNG]
The optional regression image is a screenshot with a selection at the specified location.
"""
from pathlib import Path
import subprocess, sys, tempfile
root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/OCR.swift').read_text()
helpers = source[source.index('struct OCRSelection {'):]
checks = r'''
let roi = CGRect(x: 0.2, y: 0.3, width: 0.5, height: 0.4)
let box = CGRect(x: 0.1, y: 0.2, width: 0.6, height: 0.3)
let actual = OCRGeometry.imageRect(from: box, regionOfInterest: roi)
assert(abs(actual.minX - 0.25) < 0.000001 && abs(actual.minY - 0.5) < 0.000001)
assert(abs(actual.width - 0.3) < 0.000001 && abs(actual.height - 0.12) < 0.000001)
let full = OCRGeometry.imageRect(from: box, regionOfInterest: CGRect(x: 0,y: 0,width: 1,height: 1))
assert(abs(full.minY - (1 - box.maxY)) < 0.000001 && full.minX == box.minX)
print("PASS: ROI offset, scaling, Y inversion, full-page coordinates")
if CommandLine.arguments.count > 1 {
    let url = URL(fileURLWithPath: CommandLine.arguments[1])
    let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    let selected = CGRect(x: 0.133, y: 0.497, width: 0.734, height: 0.056)
    let expanded = OCRSelection.expandedRegion(for: selected)
    let request = VNRecognizeTextRequest()
    request.recognitionLanguages = ["ja-JP", "en-US"]
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.regionOfInterest = CGRect(x: expanded.minX, y: 1-expanded.maxY,
                                     width: expanded.width, height: expanded.height)
    try VNImageRequestHandler(cgImage: image).perform([request])
    let lines = (request.results ?? []).compactMap { obs -> OCRLine? in
        guard let text = obs.topCandidates(1).first?.string else { return nil }
        return OCRLine(text: text, rect: OCRGeometry.imageRect(from: obs.boundingBox,
                                                              regionOfInterest: request.regionOfInterest))
    }
    guard let selection = OCRSelection.extract(from: lines, in: selected) else {
        fatalError("OCR recognized lines but the selected text was lost")
    }
    assert(selection.marker.contains("SSID"))
    print("PASS: curved-page screenshot selection: \(selection.marker)")
}
'''
with tempfile.TemporaryDirectory(prefix='bookmark-roi-') as temp:
    path = Path(temp) / 'check.swift'
    path.write_text('import Foundation\nimport CoreGraphics\nimport ImageIO\nimport Vision\nstruct OCRLine { let text: String; let rect: CGRect }\n' + helpers + checks)
    subprocess.run(['swift', str(path)] + sys.argv[1:], check=True)
