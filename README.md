# SameQ

世界中の知らない誰かと、同じ問いに答えるだけのSNS。

1日1回、世界共通のお題が届く。ただし通知がいつ来るかは分からない。
自分が答えて初めて、世界の誰かの答えを1件ずつ見られるようになる。
相手が何語で書いていても、本文もニックネームも最初から自分の言語・文字体系で表示される。

フォローも検索もランキングも会話もない。その日の言葉は消え、
「世界のどこかの知らない誰かも、こんなことを考えているんや」という感覚だけが残る。

## 現在の状態

スプリント02（お題のライフサイクルと投稿の寿命）まで実装済み。
初回設定 → 今日のお題 → 回答投稿 → 世界タイムライン → いいね に加えて、
お題の有効期間（28時間・常に1つだけ有効）、有効なお題が無い時間帯の**お題待ち画面**、
投稿の表示期限（お題の終了時刻に揃える）が動く。期限を過ぎると回答はタイムラインから消え、
新しいお題が始まると再び未回答状態に戻る。翻訳・通知配信・お題の自動生成・課金は後続スプリント。

### 動かす

```bash
open SameQ.xcodeproj      # 外部パッケージ依存なし。そのままビルド・実行できる

# 受け入れ条件の自動確認（ユニット6本 + UIテスト10本）
xcodebuild -project SameQ.xcodeproj -scheme SameQ \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

初回設定からやり直したいときは、アプリを削除するか、Debug ビルドに起動引数 `-SameQResetState` を付ける。

### お題の有効期間を検証する（Debug ビルド限定の起動引数）

実時間で28時間待たずに切り替わりを確認するための引数。Release ビルドでは無効。

| 引数 | 意味 |
|---|---|
| `-SameQScenario live` | 既定。お題が有効期間の途中（残り約26時間） |
| `-SameQScenario expiring` | 現在のお題がまもなく終了 → 空白（お題待ち）→ 次のお題が開始 |
| `-SameQScenario expired` | お題は終了済み、次はまだ先（お題待ち） |
| `-SameQScenario upcoming` | お題がまだ開始していない（お題待ち） |
| `-SameQExpirySeconds 120` | `expiring` で終了までの秒数（既定 180） |
| `-SameQGapSeconds 60` | `expiring` で終了から次の開始までの秒数（既定 180） |
| `-SameQTimeOffsetMinutes 90` | アプリが認識する「今」を前後にずらす |
| `-SameQDebugOverlay` | 画面下に現在時刻・お題ID・残り秒数を表示 |

### 構成

| パス | 中身 |
|---|---|
| `project.yml` | XcodeGen のプロジェクト定義（`SameQ.xcodeproj` は生成物だがコミットしてある） |
| `SameQ/Backend/` | データ層。`Backend` プロトコル、端末内実装 `LocalBackend`、お題の日程（`PromptSchedule` / `SeedCatalog`）、検証用の起動引数（`LaunchOptions`） |
| `SameQ/Feature/` | 画面（Onboarding / Waiting / Today / Timeline） |
| `SameQ/Resources/SeedData.json` | お題2件と、それぞれへの世界の回答（14件 / 12件、13言語） |
| `SameQTests/` | お題の有効期間と投稿の表示期限のユニットテスト |
| `SameQUITests/` | 受け入れ条件をなぞる UI テスト |
| `supabase/migrations/` | users / prompts / posts / likes / viewed_posts と RLS の定義 |

**注意**: Supabase のクラウドプロジェクトは作成済み・初期マイグレーション適用済みだが、
アプリはまだ `LocalBackend`（端末内）で動いており、サーバーには接続していない。
スプリント02で追加したマイグレーション（`20260817000002_prompt_lifecycle.sql`）は未適用。
詳細は [`PROGRESS.md`](PROGRESS.md) のブロッカー B01 を参照。

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
