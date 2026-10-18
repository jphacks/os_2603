"""Run on macOS with Xcode: python3 Tests/check_book_review.py.
Uses disposable SwiftData stores; never opens the app's real data.
"""
from pathlib import Path
import subprocess
import tempfile

project = Path(__file__).resolve().parents[1]
# The committed schema before textbook-review fields were introduced.
repository = project.parents[1]
baseline = subprocess.check_output([
    'git', '-C', str(repository), 'show',
    'c39cabd991a37d9d8c2ca63bbade8b00253fadfa:FusenLess/ios/Sources/Models.swift'
], text=True)
models = (project / 'Sources/Models.swift').read_text()
reader = (project / 'Sources/ReviewView.swift').read_text()
text_helpers = reader[reader.index('enum BookReviewText {'):]
main = r'''
import Foundation
import SwiftData
@main struct Check {
    @MainActor static func main() throws {
        let configuration = ModelConfiguration(url: URL(fileURLWithPath: CommandLine.arguments[1]))
        let container = try ModelContainer(for: Book.self, Sticky.self, configurations: configuration)
        let context = container.mainContext
        BODY
    }
}
'''
old_body = r'''
let book = Book(title: "教科書")
context.insert(book)
let note = Sticky(pageNumber: 417, placed: true, marker: "OCR原文", clipBefore: ["前"], clipAfter: ["後"], color: .yellow, book: book)
note.heading = "付箋の理由"
note.memo = "自分のメモ"
note.summarizedText = "要約"
note.reviewEnabled = true
note.encryptedMemo = Data([1,2,3])
note.savedPinRect = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
context.insert(note)
try context.save()
'''
new_body = r'''
let notes = try context.fetch(FetchDescriptor<Sticky>())
precondition(notes.count == 1)
let note = notes[0]
precondition(note.book?.title == "教科書" && note.marker == "OCR原文")
precondition(note.memo == "自分のメモ" && note.summarizedText == "要約")
precondition(note.encryptedMemo == Data([1,2,3]) && note.savedPinRect?.minX == 0.1)
precondition(note.reviewEnabled && !note.mastered && note.masteredAt == nil)
let date = Date(timeIntervalSince1970: 1_800_000_000)
switch CommandLine.arguments[2] {
case "queue":
    precondition(!note.needsBookReview && note.lastBookReviewAt == nil)
    note.requestBookReview()
    try context.save()
case "read":
    precondition(note.needsBookReview && note.lastBookReviewAt == nil)
    note.recordBookReview(at: date)
    precondition(!note.mastered && note.masteredAt == nil && note.reviewEnabled)
    try context.save()
case "reopen":
    precondition(!note.needsBookReview && note.lastBookReviewAt == date)
    precondition(!note.mastered && note.masteredAt == nil && note.reviewEnabled)
    note.requestBookReview()
    precondition(note.lastBookReviewAt == date)
    precondition(BookReviewText.memo(" メモ？ ? \n") == "メモ")
    precondition(BookReviewText.memo("意味？を確認") == "意味？を確認")
    precondition(BookReviewText.page(417) == "p.417")
    precondition(BookReviewText.page(0) == "ページ番号を確認してください")
    print("PASS: existing-data migration, persistent reading queue, persistent read date, mastery unchanged, display helpers")
default: fatalError("unexpected test phase")
}
'''
with tempfile.TemporaryDirectory(prefix='fusenless-review-') as temp:
    temp = Path(temp)
    source = temp / 'check.swift'
    store = temp / 'test.store'
    source.write_text(baseline + main.replace('BODY', old_body))
    subprocess.run(['swiftc', '-parse-as-library', '-module-name', 'BookReviewMigration', str(source), '-o', str(temp / 'old')], check=True)
    subprocess.run([str(temp / 'old'), str(store)], check=True)
    source.write_text(models + text_helpers + main.replace('BODY', new_body))
    subprocess.run(['swiftc', '-parse-as-library', '-module-name', 'BookReviewMigration', str(source), '-o', str(temp / 'new')], check=True)
    for phase in ['queue', 'read', 'reopen']:
        subprocess.run([str(temp / 'new'), str(store), phase], check=True)
