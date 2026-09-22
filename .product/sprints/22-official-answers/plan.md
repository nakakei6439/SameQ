# スプリント22: 手作り運営回答480件の投入

## 受け入れ条件（依頼から転記）
- [ ] official_answers テーブル作成（RLS: authenticated に select のみ）
- [ ] TSV 480行を on conflict do update で冪等投入
- [ ] ensure_official_answers() を「手作りがあれば使う、無ければ既存カテゴリ方式にフォールバック」に変更
- [ ] persona→UUID 対応は名前引き（case式）。添字を使わない
- [ ] world_timeline に is_official を追加
- [ ] ローカル db reset で適用確認、件数・本文一致・冪等性を SQL で機械照合

## 実装方針
- 新規ファイル `supabase/migrations/20260923000001_official_answers_table.sql` 1本にまとめる。
- テーブル定義 → 480行 INSERT（TSVをPythonでエスケープ生成）→ ensure_official_answers() を
  create or replace（手作り10件チェック→無ければ既存のカテゴリ配列ロジックをそのままフォールバックとして残す）
  → world_timeline を create or replace（is_official 列追加、他は不変）。
- persona→UUID は `case persona when 'keita' then '...0001' ... end` 形式の関数内ローカル
  ロジック（ja/en で別マッピング）。

## 影響範囲
- posts / users / prompts のスキーマは変更しない。
- ensure_official_answers() と world_timeline のみ再定義。既存の呼び出し元・トリガーには影響しない想定。
