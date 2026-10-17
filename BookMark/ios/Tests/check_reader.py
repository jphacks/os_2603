"""Run with python3 Tests/check_reader.py on a Mac with Xcode.
Exercises production matching/coordinate code without launching the UI.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
matching = (root / 'Sources/Matching.swift').read_text()
reader = (root / 'Sources/BookDetailView.swift').read_text()
geometry = reader[reader.index('enum ReaderCoordinates {'):]
tests = r'''
func expect(_ condition: Bool, _ message: String) {
    if !condition { fatalError(message) }
}
let marker = "この場合はANY接続を許可します。ノードがSSIDをANYとして接続すると接続を試みます。"
let lines = ["別の章", "この場合はANY接続を許可します。", "ノードがSSIDをANYとして", "接続すると接続を試みます。", "次の段落"]
expect(findBestPassage(marker: marker, lines: lines) == 1..<4, "multi-line restoration")
let reflow = ["序文", "この場合はANY接続を許可します。ノードがSSIDを", "ANYとして接続すると接続を試みます。", "終わり"]
expect(findBestPassage(marker: marker, lines: reflow) == 1..<3, "changed line breaks")
expect(findBestPassage(marker: "ANY接続を許可します", lines: lines) == 1..<2, "partial line")
expect(findBestPassage(marker: marker.replacingOccurrences(of: "許可", with: "許何"), lines: lines) == 1..<4, "OCR typo")
expect(findBestPassage(marker: "", lines: lines) == nil, "empty marker")
expect(findBestPassage(marker: "これは無関係な長い文章で全く別の内容です", lines: lines) == nil, "unrelated page")
let size = CGSize(width: 400, height: 600)
let wanted = CGRect(x: 0.2, y: 0.35, width: 0.15, height: 0.1)
for scale: CGFloat in [1, 2, 5, 8] {
    let offset = CGSize(width: 37, height: -63)
    func screen(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: (x - 0.5) * size.width * scale + size.width / 2 + offset.width,
                y: (y - 0.5) * size.height * scale + size.height / 2 + offset.height)
    }
    let a = screen(wanted.minX, wanted.minY), b = screen(wanted.maxX, wanted.maxY)
    for (start, end) in [(a,b), (b,a)] {
        let actual = ReaderCoordinates.selection(start: start, end: end, size: size, scale: scale, offset: offset)
        expect(abs(actual.minX - wanted.minX) < 0.00001 && abs(actual.width - wanted.width) < 0.00001 &&
               abs(actual.minY - wanted.minY) < 0.00001 && abs(actual.height - wanted.height) < 0.00001,
               "zoom/pan/reverse drag coordinates")
    }
}
let edge = ReaderCoordinates.selection(start: CGPoint(x: -50,y: -50), end: CGPoint(x: 500,y: 700), size: size, scale: 1, offset: .zero)
expect(edge == CGRect(x: 0,y: 0,width: 1,height: 1), "image bounds")
print("PASS: multi-line/partial/OCR-error restoration, unrelated page, zoom/pan/reverse selection, bounds")
'''
with tempfile.TemporaryDirectory(prefix='bookmark-reader-') as temp:
    source = Path(temp) / 'checks.swift'
    source.write_text('import Foundation\nimport CoreGraphics\n' + matching + geometry + tests)
    subprocess.run(['swift', str(source)], check=True)
