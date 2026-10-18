"""Verify migration from the pre-summary schema (3e2a256) without touching app data."""
from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[3]
with tempfile.TemporaryDirectory(prefix='bookmark-migration-') as temp:
    temp=Path(temp)
    old=subprocess.check_output(['git','-C',str(root),'show','3e2a256:BookMark/ios/Sources/Models.swift'],text=True)
    current=(root/'BookMark/ios/Sources/Models.swift').read_text()
    main='''
import Foundation
import SwiftData
@main struct Check {
 @MainActor static func main() throws {
  let config = ModelConfiguration(url: URL(fileURLWithPath: CommandLine.arguments[1]))
  let container = try ModelContainer(for: Book.self, Sticky.self, configurations: config)
  let context = container.mainContext
  BODY
 }
}
'''
    for name, model, body in [('old',old,'''let book = Book(title: "Migration book")
  context.insert(book)
  let sticky = Sticky(pageNumber: 12, placed: true, marker: "original OCR", clipBefore: ["before"], clipAfter: ["after"], color: .yellow, book: book)
  sticky.memo = "my memo"
  context.insert(sticky)
  try context.save()'''),('new',current,'''let notes = try context.fetch(FetchDescriptor<Sticky>())
  precondition(notes.count == 1 && notes[0].marker == "original OCR" && notes[0].memo == "my memo")
  precondition(notes[0].summarizedText == nil && notes[0].book?.title == "Migration book")
  notes[0].summarizedText = "summary"
  try context.save()
  print("PASS: existing notes migrate with original text, memo and book intact")''')]:
        source=temp/'model.swift';source.write_text(model+main.replace('BODY',body))
        binary=temp/name
        subprocess.run(['swiftc','-parse-as-library','-module-name','ReaderMigration',str(source),'-o',str(binary)],check=True)
        subprocess.run([str(binary),str(temp/'notes.store')],check=True)
