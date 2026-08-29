# SameQ プロジェクト固有ルール

グローバル設定（`~/.claude/CLAUDE.md`）の「TestFlight アップロード前の必須手順」
（README更新 → commit → push → その後にTestFlight）に加えて、このプロジェクトでは
以下も**必ず**行うこと。

## TestFlight アップロード前に追加で必須の手順

1. **GitHubへのマージを必ず先に済ませる**。ローカル commit だけで終わらせず、
   `git push` で GitHub（リモートの主ブランチ）に反映してから TestFlight へ進む。
   グローバルルールの「push を先に済ませる」を SameQ では特に厳守すること
   （TestFlightにアップロードしたのにGitHub側が古いまま、という状態を作らない）。

2. **運営お知らせ（`announcements` テーブル）に、今回のバージョンの変更内容を
   日本語・英語の両方で投入する。** SameQ にはアプリ内の「メニュー → 通知 → 運営お知らせ」
   タブで運営からのお知らせを読める機能があり（`SameQ/Feature/Notifications/NotificationsView.swift`）、
   ユーザーが新しいビルドを開いたときに「何が変わったか」を知る唯一の手段になっている。
   TestFlight にアップロードしたのにお知らせを入れ忘れると、ユーザーは変更に気づけない。

   手順（2026-08-29 に実装・運用開始）:
   - `SameQ/Info.plist` の `CFBundleShortVersionString` / `CFBundleVersion` を、
     今回のビルドの内容に合わせて更新する（App Store 正規形式 `X.Y.Z`、先頭ゼロ不可）。
   - `announcements` テーブルには `locale`（`'ja'` / `'en'` の2値のみ）カラムがある。
     日本語版・英語版を**それぞれ別の行**として投入する（1行に2言語を混在させない）。
     アプリ側は端末言語（`L10n.isJapanese` と同じ判定基準）に一致する行だけを取得する。
   - スキーマ変更が必要な場合は `supabase/migrations/` にマイグレーションを追加し、
     `supabase db push --linked` で反映する。
   - お知らせ本文の投入は `supabase db query --linked -f <SQLファイル>`（または
     `supabase db query --linked "<SQL>"`）で行う。**`.env.local` には write 権限のある
     service_role キーを意図的に置いていない**ため、REST API 経由の直接 curl 挿入はできない。
     Supabase CLI（`supabase db push --linked` / `supabase db query --linked`）が
     このプロジェクトで唯一の書き込み経路。
   - 文面のトーン: 「軽微な修正」「使い勝手の改善」のように、謝罪や不足を強調しない
     前向きな言い回しにする（`.product/spec.md` の F40 の思想と揃える）。
   - 投入後、実機またはシミュレータでメニュー → 通知 → 運営お知らせを開き、
     日英それぞれの端末言語で正しい文面が出ることを確認してから TestFlight へ進む。

この2点を飛ばして直接 TestFlight にアップロードすることを禁止する。
