// BookMark — 本の付箋アプリ 試作品のデータ型
//
// 設計メモ: ページ全体の画像は保存しない。
// 永続化するのは「本・ページ番号・目印の文字列・メモ・付箋まわりの数行の切り抜き」だけ。
// Sticky はそれを表す。

export type StickyColor = "yellow" | "pink" | "blue" | "green" | "purple";

/** 付箋の重要度（A13: 付箋だらけで重要度が分からない への対策） */
export type Importance = 1 | 2 | 3;

export interface Book {
  id: string;
  title: string;
  author?: string;
  isbn?: string;
  createdAt: number;
}

/**
 * 付箋。1枚＝本の1行に貼られた目印とメモ。
 * 画像は持たず、復元に必要な「目印」と「周辺の切り抜き」だけを持つ。
 */
export interface Sticky {
  id: string;
  bookId: string;
  pageNumber: number;
  /**
   * 行に配置済みか（A5: 写真なしで先にメモを残すモード）。
   * false のときは「位置未定のメモ」。marker/clip は空で、本を撮って
   * 行をタップすると配置され placed=true になる。
   */
  placed: boolean;
  /** 貼った行の文字列（目印）。再撮影時のあいまい一致に使う中心データ。 */
  marker: string;
  /** 目印の前の数行（本が無くても思い出すため B3）。 */
  clipBefore: string[];
  /** 目印の後の数行。 */
  clipAfter: string[];
  memo: string;
  /** 付箋ごとの一言の見出し（本番はAI。試作品では簡易生成）。 */
  heading: string;
  color: StickyColor;
  importance: Importance;
  /** 並べ替え用（A18）。小さいほど上。 */
  order: number;
  createdAt: number;
  updatedAt: number;
}

/** 試作品のサンプル本文（本番はOCR結果に相当）。 */
export interface SamplePage {
  bookId: string;
  pageNumber: number;
  lines: string[];
}
