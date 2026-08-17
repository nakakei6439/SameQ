# SameQ

世界中の知らない誰かと、同じ問いに答えるだけのSNS。

1日1回、世界共通のお題が届く。ただし通知がいつ来るかは分からない。
自分が答えて初めて、世界の誰かの答えを1件ずつ見られるようになる。
相手が何語で書いていても、本文もニックネームも最初から自分の言語・文字体系で表示される。

フォローも検索もランキングも会話もない。その日の言葉は消え、
「世界のどこかの知らない誰かも、こんなことを考えているんや」という感覚だけが残る。

## ドキュメント

- 製品仕様書: [`.product/spec.md`](.product/spec.md)（機能一覧・対象外・スプリント計画・受け入れ条件）
- 進捗管理: [`PROGRESS.md`](PROGRESS.md)（作業単位ごとのチェックリスト。セッションを跨いで再開する際はまずここを読む）

## 技術スタック（確定事項）

- iOS ネイティブ / SwiftUI、iOS 18 以降
- 翻訳: Apple Translation Framework のみ（外部翻訳APIは使用しない）
- バックエンド: Supabase（Auth / PostgreSQL / RLS / Edge Functions / Scheduled Functions）
- 認証: 匿名認証のみ
- 課金: RevenueCat（Entitlement: `plus`）
- お題生成: 生成AI APIをSupabase Edge Functionから1日1回呼び出し

## 開発フロー

このリポジトリは planner → generator → evaluator のハーネスで開発される。

1. **planner**: 短いアイデアを製品仕様書（`.product/spec.md`）に展開
2. **generator**: 仕様書のスプリントを1つずつ実装
3. **evaluator**: 実装をシミュレータ/実機・ブラウザで実際に操作して検証。必須基準を1つでも満たさなければ不合格とし、generatorが修正して再評価

進捗の詳細は [`PROGRESS.md`](PROGRESS.md) を参照。
