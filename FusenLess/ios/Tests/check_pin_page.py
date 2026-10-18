"""Run on macOS with Xcode: python3 Tests/check_pin_page.py.
Checks production numeric parsing, pin restoration, and Vision on a synthetic page.
The tiny UIImage stand-in lets the same production OCR code run on macOS.
"""
from pathlib import Path
import subprocess, tempfile
project = Path(__file__).resolve().parents[1]
reader = (project / 'Sources/PageNumberReader.swift').read_text().replace('#if canImport(UIKit)', '#if true').replace('import UIKit', '')
ocr = (project / 'Sources/OCR.swift').read_text().replace('import UIKit', '')
stub = '''
import Foundation
import CoreGraphics
import CoreText
import ImageIO
struct UIImage {
    enum Orientation { case up, down, left, right, upMirrored, downMirrored, leftMirrored, rightMirrored }
    let cgImage: CGImage?
    let imageOrientation: Orientation = .up
    init(cgImage: CGImage) { self.cgImage = cgImage }
}
'''
checks = r'''
@main struct Checks {
 static func main() async {
    for (text, expected) in [("417",417),("４１７",417),("— 417 —",417),("p.417",417),("417頁",417),("4I7",417)] {
        precondition(PageNumberResolver.parse(text)?.value == expected, "parse \(text)")
    }
    for text in ["", "0", "7.8", "第7章", "417円", "2026/10", "O", "IO", "12345"] {
        precondition(PageNumberResolver.parse(text) == nil, "reject \(text)")
    }
    func obs(_ text: String, y: CGFloat, x: CGFloat = 0.8, confidence: Float = 1) -> PageNumberObservation {
        PageNumberObservation(text: text, rect: CGRect(x: x,y: y,width: 0.05,height: 0.02),confidence: confidence)
    }
    precondition(PageNumberResolver.resolve([obs("417", y: 0.94), obs("2026",y: 0.5)]).number == 417)
    precondition(PageNumberResolver.resolve([obs("417", y: 0.94),obs("418",y: 0.94,x:0.1)]).number == nil, "ambiguous spread")
    precondition(PageNumberResolver.resolve([obs("417", y: 0.94,confidence:0.3)]).number == nil, "low confidence")
    precondition(PageNumberResolver.resolve([obs("7.8",y:0.04)]).candidates.isEmpty)
    precondition(PageNumberResolver.resolve([obs("2026",y:0.5)]).number == nil)
    let saved = CGRect(x: 0.2,y: 0.3,width: 0.15,height: 0.1)
    let wrongMatch = CGRect(x: 0.7,y: 0.8,width: 0.1,height: 0.1)
    precondition(PinRestoration.restore(saved:saved,matched:nil) == saved, "OCR failure must retain saved position")
    precondition(PinRestoration.restore(saved:saved,matched:wrongMatch) == saved, "do not overwrite manual pins")
    precondition(PinRestoration.restore(saved:nil,matched:wrongMatch) == wrongMatch, "legacy text matching")
    precondition(PinRestoration.normalized(CGRect(x: CGFloat.nan,y:0,width:0.1,height:0.1)) == nil)
    let clamped = PinRestoration.normalized(CGRect(x:-0.2,y:0.95,width:0.3,height:0.2))!
    precondition(clamped.minX >= 0 && clamped.maxX <= 1 && clamped.maxY <= 1)
    print("PASS: numeric parsing, ambiguity/false-number rejection, saved pins survive OCR failures, manual positions win, bounds")

    // A small footer number, a chapter number, and a year inside the body.
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data:nil,width:1000,height:1400,bitsPerComponent:8,bytesPerRow:0,
                        space:colorSpace,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(gray:1,alpha:1));ctx.fill(CGRect(x:0,y:0,width:1000,height:1400))
    func draw(_ text:String, x:CGFloat,y:CGFloat,size:CGFloat) {
        let font = CTFontCreateWithName("Helvetica" as CFString,size,nil)
        let attributes = [kCTFontAttributeName:font,kCTForegroundColorAttributeName:CGColor(gray:0,alpha:1)] as CFDictionary
        let string = CFAttributedStringCreate(nil,text as CFString,attributes)!
        ctx.textPosition = CGPoint(x:x,y:y)
        CTLineDraw(CTLineCreateWithAttributedString(string),ctx)
    }
    draw("Sample textbook",x:100,y:1320,size:28)
    draw("7.8",x:900,y:1300,size:20)
    draw("2026",x:200,y:700,size:22)
    draw("This page contains text and diagrams.",x:120,y:1100,size:20)
    draw("417",x:900,y:24,size:16)
    let result = await PageNumberReader.read(UIImage(cgImage:ctx.makeImage()!))
    precondition(result.number == 417,"small footer OCR: \(result.candidates)")
    print("PASS: production Vision pipeline recognizes small footer 417 and rejects chapter 7.8 and body year 2026")
    let tilted = CGContext(data:nil,width:1000,height:1400,bitsPerComponent:8,bytesPerRow:0,
                           space:colorSpace,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    tilted.setFillColor(CGColor(gray:0.85,alpha:1));tilted.fill(CGRect(x:0,y:0,width:1000,height:1400))
    tilted.translateBy(x:500,y:700);tilted.rotate(by:5 * .pi / 180)
    tilted.draw(ctx.makeImage()!,in:CGRect(x:-500,y:-700,width:1000,height:1400))
    let tiltedResult = await PageNumberReader.read(UIImage(cgImage:tilted.makeImage()!))
    precondition(tiltedResult.number == 417, "tilted page: \(tiltedResult.candidates)")
    print("PASS: slightly tilted synthetic page still resolves footer 417")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='fusenless-pin-page-') as temp:
    temp=Path(temp)
    source=temp/'check.swift';source.write_text(stub+ocr+reader+checks)
    subprocess.run(['swiftc','-parse-as-library',str(source),'-o',str(temp/'check')],check=True)
    subprocess.run([str(temp/'check')],check=True)

# Persist a real SwiftData pin, reopen the process, move it, and reopen again.
persistence = r"""
import SwiftData
@main struct Persistence {
 @MainActor static func main() throws {
    let config = ModelConfiguration(url: URL(fileURLWithPath: CommandLine.arguments[1]))
    let container = try ModelContainer(for: Book.self, Sticky.self, configurations: config)
    let context = container.mainContext
    switch CommandLine.arguments[2] {
    case "write":
        let book = Book(title: "Pin test book")
        context.insert(book)
        let note = Sticky(pageNumber:417,placed:true,marker:"原文",clipBefore:[],clipAfter:[],color:.yellow,book:book)
        note.savedPinRect = CGRect(x:0.2,y:0.3,width:0.15,height:0.1)
        note.memo = "メモ"
        context.insert(note)
        try context.save()
    case "move":
        let notes = try context.fetch(FetchDescriptor<Sticky>())
        precondition(notes.count == 1)
        let note = notes[0]
        precondition(note.pageNumber == 417 && note.book?.title == "Pin test book")
        let original = CGRect(x:0.2,y:0.3,width:0.15,height:0.1)
        precondition(PinRestoration.restore(saved:note.savedPinRect,matched:nil) == original)
        precondition(PinRestoration.restore(saved:note.savedPinRect,matched:CGRect(x:0.7,y:0.8,width:0.1,height:0.1)) == original)
        note.savedPinRect = CGRect(x:0.6,y:0.5,width:0.15,height:0.1)
        try context.save()
    case "verify":
        let note = try context.fetch(FetchDescriptor<Sticky>())[0]
        precondition(note.savedPinRect == CGRect(x:0.6,y:0.5,width:0.15,height:0.1))
        precondition(note.memo == "メモ" && note.pageNumber == 417)
        print("PASS: saved pin restored after process restart, manual move persists, page and memo unchanged")
    default: fatalError("unexpected phase")
    }
 }
}
"""
with tempfile.TemporaryDirectory(prefix='fusenless-pin-store-') as temp:
    temp = Path(temp)
    source = temp / 'check.swift'
    models = (project / 'Sources/Models.swift').read_text()
    pure_reader = reader.split('#if true')[0]
    source.write_text(models + pure_reader + persistence)
    binary = temp / 'check'
    subprocess.run(['swiftc','-parse-as-library',str(source),'-o',str(binary)],check=True)
    for phase in ['write','move','verify']:
        subprocess.run([str(binary),str(temp / 'pins.store'),phase],check=True)
