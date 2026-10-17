# BookMark — 本の付箋アプリ（試作品）

借りた本でも、自分の本のように書き込みながら学び、後から思い出せる。
JPHACKS2026 の体験検証用プロトタイプ（iPhoneブラウザで動くWebアプリ）。
本番は iPhone ネイティブ（Swift・端末内OCR・端末内AI）予定。

## 公開URL（iPhone実機はこちら）

**https://dist-one-henna-99.vercel.app/**

- Vercel にデプロイ済み。iPhone Safari でどの回線でも開ける（キャンパスWi-Fi等の制限を回避）
- ※ Claude の Artifact 公開はサンドボックス(CSP)でOCRのWeb Workerがブロックされ0%で止まるため不可。
  通常の静的ホスト(Vercel)を使う。

## 動かす（ローカル開発）

```bash
npm install
npm run dev
```

- データはブラウザの localStorage に保存（端末内のみ）

## 再デプロイ

```bash
npx vite build
vercel deploy dist --prod --yes
```

- 同じ本番URL（dist-one-henna-99.vercel.app）に上書きされる
- `vercel` CLI はログイン済み（アカウント: tonama1226-9780）

## いまできること（土台）

- 本棚：サンプル本2冊＋本の追加（ISBNは手入力。バーコード読取は本番で）
- 撮影タブ：
  - **📷 カメラで撮る**：実際の本の写真を撮影 → 端末内OCR（Tesseract.js, jpn+eng）で
    本文とページ番号を認識 → **既存の付箋を対応行に自動配置** → 写真の行をタップで付箋（B1）
  - **🧪 サンプル画像でOCR**：カメラが無い環境でも同じOCR→自動配置の流れを確認できる
  - サンプルページ（撮影の再現）：行をタップで一瞬で付箋（B1）
- 「撮り直しを再現」：OCRのズレ（文字ノイズ＋行オフセット）を入れても、
  **目印のあいまい一致で付箋が元の行に戻る**（設計の核・AIではなくアルゴリズム）
- 付箋編集：メモ（手入力＋🎤音声）／色／重要度（★）／削除
- 一覧タブ：小口ビュー（本の側面＝B2）＋付箋リスト（並べ替え＝A18）
- パラパラモード：本が無くても周辺の文章で思い出す（B3）
- 復習モード：周辺文 → 見出し/メモ の暗記カード
- 本をまたいだ付箋検索（A16）

## 設計の決定（コードに反映済み）

- ページ全体の画像は保存しない。保存するのは
  本・ページ番号・目印の文字列・メモ・付箋まわりの数行の切り抜きだけ（`src/types.ts`）
- ページ特定と付箋復元は目印のあいまい一致（`src/matching.ts`、Levenshtein）
- AIの役割は「一言の見出し」と「復習問題」に限定（試作では簡易生成 `makeHeading`）

## カメラ + OCR の注意点

- iPhone のカメラは `<input capture>` を使うため **http の LAN URL でも撮影できる**
  （getUserMedia と違い https 不要）
- 初回OCRは日本語辞書（数MB）をCDNから読み込むため時間がかかる。以降はキャッシュ
- 実写真のOCR精度は明るさ・角度に依存。ページ番号が読めないときは上部の ✎ で手入力
- OCR言語は `src/ocr.ts` の `createWorker("jpn+eng", ...)` で変更可

## 次のステップ候補

- B1/B3/B4 の体験の磨き込み（メンター指摘の中心）
- OCRの前処理（傾き補正・二値化）で実写真の精度を上げる

## 構成

- `src/App.tsx` 画面と導線（本棚／撮影／一覧／追加）／カメラ撮影・OCR導線
- `src/store.ts` 状態と localStorage、見出し生成
- `src/matching.ts` 目印のあいまい一致
- `src/ocr.ts` 端末内OCR（Tesseract.js）：行＋位置の抽出、ページ番号検出
- `src/PhotoReader.tsx` 写真の上に行オーバーレイ・付箋配置
- `src/sampleImage.ts` サンプル本文を画像化（OCR検証・デモ用）
- `src/StickyEditor.tsx` 付箋編集シート
- `src/FlipMode.tsx` パラパラモード
- `src/ReviewScreen.tsx` 復習モード
- `src/sampleData.ts` サンプル本・本文（撮影の再現用）

## iPhoneネイティブ版（本命・`ios/`）

Web試作で体験・設計を検証後に着手した本番版。SwiftUI + SwiftData、OCRは端末内 **Apple Vision**（日本語）。

### 動かす
```bash
cd ios
xcodegen generate   # project.yml から Xcodeプロジェクトを生成
open BookMark.xcodeproj
```
Xcodeで Signing（自分のTeam）を設定し、実機またはシミュレータで実行。

### 構成（`ios/Sources/`）
- `BookMarkApp.swift` エントリ・ModelContainer
- `Models.swift` SwiftData（Book / Sticky）。画像は保存せず目印＋切り抜き＋メモ
- `Matching.swift` 目印のあいまい一致（Web版から移植）
- `OCR.swift` Apple Vision（`VNRecognizeTextRequest`, ja-JP）＋ページ番号検出
- `SampleImage.swift` サンプルページ画像（OCR検証用）
- `ShelfView.swift` 本棚
- `BookDetailView.swift` 撮影・写真ビュー・付箋作成/自動配置・編集

### できていること
本棚→カメラ/写真/サンプル→Vision OCR→ページ自動認識→行タップで付箋→あいまい一致で自動配置→編集（メモ/色/重要度/削除）→一覧。

### 未実装（次段）
音声メモ（Speech）、パラパラモード、復習、クイックメモ(A5)、本またぎ検索。
