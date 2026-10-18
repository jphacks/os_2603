# BookMark（本の付箋アプリ・iOS）

借りた本でも、自分の本と同じように書き込みながら学び、後から思い出せる。
本はきれいなまま、学んだことはアプリに残す「本の付箋」アプリ（iPhoneネイティブ）。

## 使い方
1. 本を選ぶ（起動時は最後に開いた本の撮影画面から始まる）
2. ページを撮る（カメラ／写真／サンプル画像）
3. **付箋を貼りたい部分を指でなぞって囲む** → その範囲だけOCR → 付箋ができる
4. メモは後から。色・重要度で整理
5. **パラパラモード**で本が無くても周辺の文章で思い出す／**復習**で暗記
6. 次に同じページを撮ると、付箋が元の行に自動で戻る

## 技術
- SwiftUI / SwiftData（iOS 17+）
- 端末内OCR: **Apple Vision**（`VNRecognizeTextRequest`, 日本語）。
  囲んだ範囲だけ `regionOfInterest` で読む（ページ全体は原則読まない＝プライバシー・速度）
- 付箋の復元は「目印の文字列のあいまい一致」（AIではなくアルゴリズム）

## ビルド
```bash
cd ios
xcodegen generate     # project.yml から Xcodeプロジェクトを生成
open BookMark.xcodeproj
```
Xcode で Signing（自分の Team）を設定し、実機またはシミュレータで実行。

## 構成（`ios/Sources/`）
- `BookMarkApp.swift` エントリ・ModelContainer（ライト固定）
- `Models.swift` SwiftData（Book / Sticky）。画像は保存せず目印＋切り抜き＋メモ
- `Matching.swift` 目印のあいまい一致（再撮影時の付箋復元）
- `OCR.swift` Apple Vision（`regionOfInterest` 対応）＋ページ番号検出
- `Store.swift` 最後の本／本ごとの最後のページを記憶（最短動線）
- `ShelfView.swift` 本棚（起動時に最後の本へ）
- `BookDetailView.swift` 撮影・範囲選択で付箋作成・自動配置・編集
- `FlipView.swift` パラパラモード（B3）／ `ReviewView.swift` 復習モード
- `SampleImage.swift` サンプルページ画像（OCR確認用）

## 設計の核
- ページ全体の画像は保存しない。保存は「本・ページ番号・目印・メモ・周辺の切り抜き」だけ
- 「囲む＝付箋＝OCR範囲」で操作を増やさない
- 物理の付箋の良さ（一瞬で貼れる・パラパラで思い出す・多くても区別できる）を最優先

## 今後
音声メモ（Speech）、本またぎ検索・並べ替え、端末内AIによる見出し／復習問題の自動生成、縦書き対応。
