# スプリント 12 attempt 6: 指摘 [2][3] に対応

## eval-4.md の不合格理由（要約）
- **[1]**（ユーザー側対応必須）Supabase プロジェクトで匿名サインインが無効化されている
- **[2]**（generator 側で対応可能・新規発見）オンボーディング完了処理の失敗がユーザーに一切表示されない
- **[3]**（ユーザー側対応必須、self-review.mdの申し送りと同じだが内容を訂正）保留中の migration 自体が壊れている（`posts.decorations` 列を参照しているが、追加する `ALTER TABLE` が無い）

## 着手可能な範囲（generator 側）
- **[2]** をコードで修正する: `OnboardingView` に `session.alertMessage` を購読する `.alert(...)` を追加する
- **[3]** をコードで修正する: `supabase/migrations/20260819000004_server_connection.sql` に `posts.decorations` と `prompts.language` 等の必要な `ALTER TABLE` を追加し、migration 単体で push 可能にする

## 着手できない範囲（ユーザー側）
- **[1]** Supabase ダッシュボードで匿名サインインを有効化する
- seed データの投入とアクセストークンの取得

## 影響範囲
- 既存の migration 1〜3 には影響しない（`if not exists` 句付きの `alter table` を追加するだけ）
- OnboardingView への `.alert` 追加は、TodayPromptView / TimelineView の alert とは独立した新しい `.alert`（同じ `alertMessage` を購読するが、`isTimelinePresented` と無関係に立つ）

## 完了条件
- 受け入れ条件7「失敗したことが画面上に表示され、同じ操作をもう一度試せる」が、オンボーディング中のアカウント作成失敗時にも成立する（[2] の修正）
- `supabase db push` で `20260819000004_server_connection.sql` がエラー無く適用できる（[3] の修正）
- 既存ユニット 166/166・UI 回帰テスト（既存 4 スプリント分）が引き続き成功