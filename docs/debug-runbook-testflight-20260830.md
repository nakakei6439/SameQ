# SameQ TestFlight フィードバック デバッグランブック（2026-08-30）

3 件の TestFlight フィードバック（`nakakei6439@gmail.com` / iPhone18_2 / iOS 26.6.1）
に共通する「通知→お題画面→回答→世界タイムライン」のフローで観測された不具合と、
その再現手順・修正・確認方法をまとめたドキュメント。

## フィードバック一覧（App Store Connect API より取得）

| # | 発生時刻 (JST) | 種別 ID | コメント | スクショ |
|---|---|---|---|---|
| ① | 2026-08-30 14:25 | `AGaXQ-etsd-vs7Ai2OmrmkY` | 新しい通知が届きました。開いたらこの画面でした。 | 「いまはお題がありません」画面 |
| ② | 2026-08-30 11:26 | `AEIdNn3LYA5pRAkIXRs-rss` | 新しいお題が来ましたとらありますがエラーです | セッション切れアラート |
| ③ | 2026-08-30 10:04 | `AJJhdZrwmZ-1xU48eT2cHKk` | お題が違う / 書けない | 自分の回答表示・composer 非表示 |

**取得方法**（再現・追加調査用）:

```bash
# 1) JWT を生成
KEY_ID="BR882VJ4P8"
ISSUER_ID="4a7eba90-53ca-4945-ae45-78facdf6f085"
KEY_PATH="/Users/nakagawakeita/Products/iOSApp/KondateCart/resources/certificates/AuthKey_${KEY_ID}.p8"

# PyJWT + cryptography が必要（Homebrew Python の PEP 668 回避で venv を作る）
python3 -m venv /tmp/asc-venv
/tmp/asc-venv/bin/pip install pyjwt cryptography

JWT=$(/tmp/asc-venv/bin/python - <<PY
import jwt, time
with open("$KEY_PATH", "rb") as f: pk = f.read()
now = int(time.time())
print(jwt.encode(
    {"iss": "$ISSUER_ID", "iat": now, "exp": now+1200, "aud": "appstoreconnect-v1"},
    pk, algorithm="ES256", headers={"kid": "$KEY_ID", "typ": "JWT"}))
PY
)

# 2) フィードバック一覧（App ID 6805425491 = SameQ）
curl -sS -H "Authorization: Bearer $JWT" \
  "https://api.appstoreconnect.apple.com/v1/apps/6805425491/betaFeedbackScreenshotSubmissions?limit=50" \
  | jq '.data[] | {id, createdDate: .attributes.createdDate, comment: .attributes.comment}'
```

スクリーンショット URL は `?Expires=1788480000` (= 2026-09-04) で失効するため、
**保存期限はフィードバック作成から数日のみ**。恒久的に残したい場合は TestFlight の
Web UI（App Store Connect → SameQ → TestFlight → フィードバック）か、画像として
ダウンロードして `docs/testflight-feedback/` などに保存する。

---

## ① 通知発火 → 「いまはお題がありません」

### 症状
- 8:00〜22:00 JST のランダムな時刻に届いた通知をタップ
- ホーム画面で「いまはお題がありません / 次のお題が届くまで、少し待ってください」になる
- 数分後に再度開くと普通に表示される

### 根本原因
- プロンプトは UTC 00:00 = JST 09:00 始まり、28 時間後 (= JST 13:00) 終わり
- 同じ曜日の 28h 周期 = 4h の「**お題不在ギャップ**」が毎日必ず存在する
  - 具体的には `currentPrompt.endsAt` (例: JST 13:00) から `nextPrompt.startsAt` (例: 翌 JST 09:00) のあいだ
- 通知ウィンドウ 8:00〜22:00 JST のうち、8:00〜9:00 と 13:00〜22:00 の **一部** は
  このギャップにかかる可能性がある
- 実機観測の 14:23 JST については「ギャップ」でなく「自己修復 RPC が一時失敗して
  waiting にフォールバック」が主因の可能性もある（両方の対策を入れておく）

### 修正
- `NotificationTimePicker.pickNextDate(...)` に **`earliestFireDate: Date?`** 引数を追加
- `AppSession.scheduleDailyReminderIfPossible()` が
  `currentPrompt.endsAt + 4h + 30m` (= 次プロンプトの `startsAt` + 30 分マージン)
  を `earliestFireDate` として渡す
- 候補が `earliestFireDate` 未満のときは翌日に送る
- 関連変更:
  - `SameQ/Backend/NotificationScheduler.swift` — プロトコル・`LiveNotificationScheduler`・`FakeNotificationScheduler` すべてに `earliestFireDate` 引数を伝播
  - `SameQTests/NotificationSchedulingTests.swift` — 4 件の境界値テスト追加

### 動作確認手順
1. `xcodebuild test -scheme SameQ -destination 'platform=iOS Simulator,name=iPhone 18 Pro'`
2. `NotificationSchedulingTests` の以下の 4 ケースが通ること:
   - `testPickNextDate_defersToNextDayWhenEarliestFireDateSkipsToday`
   - `testPickNextDate_earliestFireDateAfterWindowForcesTomorrow`
   - `testPickNextDate_earliestFireDateSameAsNowUsesFloor`
   - `testPickNextDate_earliestFireDateNilMatchesNowOnlyBehavior`
3. 実機 / シミュレータで `-SameQNotificationHour 8` を付けて起動し、
   プロンプトの `endsAt` 直前の 21:00 JST に手動で `scheduleDailyReminderIfPossible()`
   を呼ぶと、翌 8:00 JST に予約される（翌日の 09:00 ギャップを跨がない）

### デバッグログ
- Debug ビルドで `-SameQDebugOverlay` を付けると、画面下に
  `now <時刻> srv <サーバ時刻> scenario <...> prompt_<id> ends in <秒>s` が表示される
- `SameQ/Backend/NotificationScheduler.swift` の `pickNextDate` に
  `print("[SameQ] pickNextDate: floor=... candidate=...")` を仕込むと
  ギャップ回避の挙動を CLI から確認できる

---

## ② 「セッションが切れました」アラート

### 症状
- 起動から時間が経って（実機観測は通知着弾の 14:23 JST 時点で、起動は同日 04:00 頃）
- 「世界の回答」を開いた直後に「うまくいきませんでした / セッションが切れました」アラート

### 根本原因
- Supabase の `access_token` は既定で 1 時間で失効
- 既存修正（2026-08-29 コミット `8ad321a`）では `start()` で
  `ensureFreshSession()` を呼ぶが、**1 秒ごとの `refresh()` ループでは再取得しない**
- 起動 1 時間を超えると、認証付き API が 401 で失敗し始める
- 「もう一度やり直す」を押しても、同じ古いトークンで再試行するだけ（観測済みの二次不具合）

### 修正
- `AppSession` に `lastSessionRefreshAt: Date?` と
  `sessionRefreshInterval: TimeInterval = 50 * 60` を追加
- `start()` で `ensureFreshSession()` 直後に `lastSessionRefreshAt = clock.now`
- `refresh()` の冒頭で「最終リフレッシュから 50 分以上経過していたら
  `ensureFreshSession()` を 1 度だけ走らせる」軽量ガードを追加
- `ensureFreshSession()` 自体は冪等（リフレッシュ失敗時は何もせず、
  `state` を壊さない）なので、毎秒走らせても問題ないが、API 呼び出しを
  最小限にするため 50 分間隔に絞る

### 動作確認手順
1. ビルドして起動（`Date.now() = T0`）
2. 50 分経たないうちに `refresh()` を呼んでも `ensureFreshSession()` は走らない
   （`AppClock` を注入できるテストなら、それで「50 分後」をエミュレートできる）
3. 50 分以上経過後に `refresh()` を呼ぶと、`backend.ensureFreshSession()` が 1 回呼ばれる
4. 受け入れ条件: 起動から 24 時間経過しても、`openTimeline()` が 401 を返さない

### デバッグログ
- `SupabaseBackend.ensureFreshSession()` 内に `print(...)` を仕込むと、
  リフレッシュが走った実時刻が分かる
- `-SameQDebugOverlay` で `now <T>` が `lastSessionRefreshAt` の差分も追加すると良い

---

## ③ 「お題が違う / 書けない」

### 症状
- ホーム画面に「あなたの回答: 散歩です！！」が出ている
- スクショ 2 枚目では「世界の回答 → まだ誰も答えていません」
- ユーザーは「composer が出てこないので書けない」「お題が前日のように見える」と感じている

### 根本原因
- 仕様 F04 / F17 で「**1つのお題に 1 回だけ**」が確定仕様。`posts` テーブルには
  `constraint posts_one_per_prompt unique (prompt_id, author_id)` もある
- `TodayPromptView` の分岐:
  ```swift
  if let myPost = session.myPost {
      answeredSection(myPost: myPost)   // composer は出ない
  } else {
      composer                          // 入力欄が出る
  }
  ```
- スクショの「お題が違う」はおそらく **「翌日のプロンプトを期待していたが、
  同一日のお題（前のお題と dayIndex が偶然同じなど）が出ていた」** 程度の
  主観的コメントで、実装的バグではない可能性が高い
- 確認: `SupabaseBackend.myPost(promptID:)` は `prompt_id = '<current id>' AND
  author_id = ...` で正しく絞っているため、**前日のお題の回答が今日に漏れる
  コード欠陥は無い**

### 修正
- `answeredSection` 末尾に「あなたの回答は確定しました。次のお題は新しい一日に届きます。」
  というヒント（L10n.Today.answeredHint）を表示
- アイコンは `checkmark.seal.fill`、アクセシビリティ識別子は `today.answeredHint`
- これにより「書き直せない / 別のお題？」の混乱を緩和

### 将来的な検討事項（今回は未対応）
- 「お題を編集」機能（`posts` テーブルに `updated_at` を追加し、`update` 権限を
  `prompt.endsAt > now` の間だけ許可する RLS ポリシー）— 仕様変更なので
  `.product/spec.md` の合意が必要
- 1 投稿の文字数上限（140 / Plus 2000）を超えた場合にどう通知するか

---

## 全体: 変更ファイルと影響範囲

| ファイル | 変更種別 | 影響 |
|---|---|---|
| `SameQ/Backend/NotificationScheduler.swift` | 機能追加 | `NotificationTimePicker`・`LiveNotificationScheduler`・`FakeNotificationScheduler` のシグネチャ拡張（デフォルト引数で後方互換） |
| `SameQ/Session/AppSession.swift` | 機能追加 | `scheduleDailyReminderIfPossible()` で `earliestFireDate` を渡す / `refresh()` で 50 分間隔の `ensureFreshSession()` / `lastSessionRefreshAt` プロパティ追加 |
| `SameQ/Feature/Today/TodayPromptView.swift` | UI 追加 | `answeredSection` 末尾に `answeredHint` カードを追加 |
| `SameQ/L10n.swift` | 文言追加 | `L10n.Today.answeredHint`（日英） |
| `SameQTests/NotificationSchedulingTests.swift` | テスト追加 | ギャップ回避ロジックの 4 ケース |
| `supabase/migrations/20260830000014_*.sql` | **真の根本原因** | `ensure_todays_prompt()` が `prompts_no_overlap` 制約違反で INSERT 失敗していたバグを修正 |

## 🚨 真の根本原因（実機 / フィードバック ① 共通）

**2026-08-30 19:27 JST の実機検証で発覚。** 上記の Swift 修正（通知発火タイミング）
は**対症療法に過ぎず、本当の根本原因は DB 側**でした。

### 症状
- 19:27 JST（Day 30 プロンプトの active 期間内）でも「いまはお題がありません」固定
- `promptState()` の自己修復 RPC `ensure_todays_prompt()` が silent に失敗

### 直接の原因
- マイグレーション 02（`20260817000002_prompt_lifecycle.sql`）で
  ```sql
  alter table public.prompts add constraint prompts_no_overlap
      exclude using gist (tstzrange(starts_at, ends_at, '[)') with &&);
  ```
  が追加されている
- 一方 `Prompt.defaultDuration` は 28 時間、`startOfDay` は UTC 00:00
- 結果、Day 29 [08-29 00:00, 08-30 04:00) と Day 30 [08-30 00:00, 08-31 04:00) は
  必ず **4 時間 overlap** する
- マイグレーション 13（`20260829000013_ensure_todays_prompt.sql`）の
  `ensure_todays_prompt()` はこの overlap を考慮しておらず、
  `INSERT ... on conflict (id) do nothing` で必ず
  ```
  23P01 conflicting key value violates exclusion constraint "prompts_no_overlap"
  ```
  で失敗する
- Swift 側 `try?` で握り潰されるので、ユーザーは「waiting 固定」しか見ない

### 修正
- マイグレーション 14（`20260830000014_fix_ensure_todays_prompt_overlap.sql`）
- `ensure_todays_prompt()` 内で INSERT 直前に
  ```sql
  update public.prompts
  set ends_at = v_starts_at
  where ends_at > v_starts_at
    and starts_at < v_starts_at;
  ```
  で「直前プロンプトの `ends_at` を新プロンプトの `starts_at` に切り詰める」
  前処理を追加
- 28h 有効の意図は維持（切り詰めは最大 4h のみ）
- 制約も生かす（整合性チェックは有用なので）

### 検証手順
```sql
-- 関数単体の動作確認
select public.ensure_todays_prompt();
-- 結果
select id, text, starts_at, ends_at,
       (now() >= starts_at and now() < ends_at) as is_active
  from public.prompts
 order by starts_at desc limit 5;
-- → prompt_20260830 が is_active=true で出れば OK
-- → 古い prompt_20260829 は ends_at が trunc されて 24h になっている
```

### アプリ側の確認
- 既に DB が直っているので、アプリを**再起動 or 1 秒待って refresh()** すれば
  新しいプロンプトが画面に出る
- 実機で確認した 19:27 JST のスクショは、関数実行前は「waiting」、
  関数実行後は「もし一日だけ、どこか知らない街を歩けるとしたら何を持って歩きますか？」
  が表示された

### 同根で直るもの
- フィードバック ①: 通知タップ後にお題が出ない
  （自己修復 RPC が毎回失敗していたため、`prompts` が恒久的に空だった）
- 毎日 0:00 UTC を跨いだ瞬間に今後必ず起きていた**潜在バグ**

## 検証手順（CI / ローカル共通）

```bash
cd /Users/nakagawakeita/Products/iOSApp/SameQ-fix-testflight-feedback
xcodebuild -project SameQ.xcodeproj -scheme SameQ \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=latest' \
  test 2>&1 | tail -40
```

合格基準:
- `NotificationSchedulingTests`: 4 件すべて pass
- 既存の `AppSession.start()` / `refresh()` 関連テストが pass
- 既存の `L10n` / `TodayPromptView` のスナップショットテスト（あれば）が pass

## ロールバック手順

ロールバックが必要になった場合は:

```bash
# worktree なので main ブランチは無傷
cd /Users/nakagawakeita/Products/iOSApp/SameQ
git worktree remove ../SameQ-fix-testflight-feedback --force
git branch -D fix/testflight-feedback-20260830
```

`merge --no-ff` 後であれば:

```bash
git revert -m 1 <merge-commit-sha>
git push origin main
```

## 参考: 2026-08-29 緊急対応の履歴

- コミット `8ad321a`: `ensureFreshSession()` を `start()` に追加（実機観測）
- コミット `2708221`: `ensure_todays_prompt()` SQL 関数 + `promptState()` の自己修復呼び出し
- マイグレーション `20260829000013_ensure_todays_prompt.sql`

これらは「修正が効いている前提」で組まれている。今回のフィードバックは
「修正が効いたあとに残る境界条件」が観測されたので、上記 3 件と組み合わせて
本番に投入する。
