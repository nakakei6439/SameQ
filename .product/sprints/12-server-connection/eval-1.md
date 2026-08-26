# スプリント 12 評価（attempt 1） — 不合格

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 0/8 | 100% | ✗ |
| 2 動作の安定性 | クラッシュ0 だが主要動線が1歩も完走できない | 主要動線が最後まで通る | ✗ |
| 3 データ整合性 | 検証不能（サーバー操作が1件も成功しない） | 100% | ✗ |
| 4 回帰 | 12/12 サンプルのUIテストが失敗（要求は最低3件） | 100% | ✗ |
| 5 使用性の最低線 | 1（完走できない） | 3以上 | ✗ |

**5基準すべてが閾値を下回っており不合格。** 原因は1点に集約される：アプリが接続する Supabase プロジェクト（`loqumzfgnahtclnvnrzb`）が実際には存在しない／到達不能なため、既定の起動経路でアプリが最初の画面から一歩も進めない。

## 検証環境
- 端末: iPhone 17 シミュレータ（`12050FBD-587B-4910-8812-696BB91BE051`）と iPhone 17 Pro シミュレータ（`4C9A260E-CC74-4DE6-AE65-509C6FC2F43E`）、iOS 26.5、2台同時起動
- ビルド: `xcodegen generate` → `xcodebuild -project SameQ.xcodeproj -scheme SameQ -destination 'platform=iOS Simulator,...' build`（BUILD SUCCEEDED）
- 起動: `xcrun simctl launch <device> com.nakakei6439.SameQ`（引数なし＝self-review.md記載の「通常起動（Supabase 経由・既定）」の手順どおり）
- 実施時刻: 2026-08-26 13:14〜13:20 JST
- 自動テスト: `xcodebuild -only-testing:SameQTests test`（166本 全成功）、`-only-testing:SameQUITests/SprintOneAcceptanceTests`（5本 全失敗）、`-only-testing:SameQUITests/SprintFiveAcceptanceTests`（7本 全失敗）

## 不合格の原因（これを直せば通る）

### [1] Supabase プロジェクトが存在せず、アプリが起動直後から一切先に進めない（受け入れ条件1〜7すべてが検証不能かつ実質未達）
- **再現手順**:
  1. `xcodegen generate` → シミュレータ向けにビルド
  2. 2台のシミュレータ（iPhone 17 / iPhone 17 Pro）へインストール
  3. 引数なしで起動（self-review.md記載の「通常起動」手順そのまま）: `xcrun simctl launch <device> com.nakakei6439.SameQ`
  4. 両端末とも起動から約2秒で「読み込めませんでした／通信できません。ネットワーク接続を確認してください。」の画面のまま止まる
- **期待**: spec.md 300〜313行のとおり、端末A・Bがオンボーディングを完了し、今日のお題に回答し、互いの回答をタイムラインで読み、いいね・通報・ブロックが反映されること
- **実際**: オンボーディング画面にすら到達しない。「もう一度試す」を押しても再度同じ通信エラーになる（サーバーが存在しないため物理的に成功しえない）
- **根拠**（3系統の独立した証拠。すべて一致）:
  1. **DNS解決の失敗**: `dig @8.8.8.8 +short loqumzfgnahtclnvnrzb.supabase.co` が NXDOMAIN。同一シェルから `https://www.google.com` は200で取得でき、`aws-0-ap-northeast-1.pooler.supabase.com`（Supabaseのプーラー）も名前解決できるため、ネットワーク全体やサンドボックスの制限ではなく、このプロジェクト固有のホスト名だけが存在しない
  2. **Supabase CLI による確認**: `supabase migration list --linked` の実行結果が `FATAL: (ENOTFOUND) tenant/user postgres.loqumzfgnahtclnvnrzb not found`。プーラー自体には接続できるが、Supabase側がテナント（プロジェクト参照 `loqumzfgnahtclnvnrzb`、`.env.local` と `SupabaseConfig.swift` にハードコードされているものと同一）の存在を否定している
  3. **実機（シミュレータ）での再現**: 2台のシミュレータで実際にアプリを起動し、両方とも同じ通信エラー画面で完全に停止することを画面キャプチャで確認（`evidence-deviceA-offline-error.png` / `evidence-deviceB-offline-error.png`）
  - 詳細ログは `.product/sprints/12-server-connection/evidence-network-diagnosis.txt` を参照
- **切り分け**: `-SameQUseLocalBackend` を付けて起動すると同じビルドで正常にオンボーディング画面が表示される（`evidence-localbackend-onboarding-still-works.png`）ため、アプリ側のロジック自体は壊れていない。問題は Supabase プロジェクトの存在・到達性、または `SupabaseConfig.swift` に埋め込まれた URL の誤りに限定される

### [2] 既存の per-sprint UIテスト（回帰の自動化資産）が既定の起動引数のまま新しい既定バックエンドに乗り換わり、軒並み失敗する
- **再現手順**: `xcodebuild -only-testing:SameQUITests/SprintOneAcceptanceTests test` および `SprintFiveAcceptanceTests` を実行
- **期待**: スプリント01・05で合格していた受け入れ条件（オンボーディング順序、いいねの永続化、アカウントの再起動後の維持、二重投稿の拒否、通報・いいねの連打制限、BANアカウントの画面、BANされた投稿者の非表示など）が引き続き成立する
- **実際**: SprintOneAcceptanceTests 5/5 失敗、SprintFiveAcceptanceTests 7/7 失敗。すべて `onboarding.next` ボタンが見つからず（画面には代わりに「もう一度試す」ボタンが存在）タイムアウト
- **根拠**: xcodebuild のテスト出力（本評価の実行ログに保存済み）。原因は [1] と同一（テストが `app.launchArguments = []` などデフォルト起動のままで、`BackendProvider` の既定が `SupabaseBackend` に変わったため）
- **これは合否とは独立に見ても重大**: self-review.md は「実機検証は evaluator 担当」「ユニットテストのみ実行」と述べているが、**既存のUIテストスイート（自動化された回帰資産）すら1本も実行せずに `awaiting_eval` として引き渡している**。これらを実行していれば、Supabaseプロジェクトの到達性問題は generator 側で検出できたはずである

### [3] self-review.md 内で generator 自身が認識している未解決の懸念（今回は検証不能だが記録として残す）
- `decorations` カラムが Supabase 側の `posts` テーブルに未追加（self-review「自分で見つけた弱点3」）。マイグレーション `20260819000004_server_connection.sql` の適用状況自体、サーバーに接続できないため今回確認できていない
- トークン失効時の自動リフレッシュ未実装（弱点1）。長時間起動しっぱなしのシナリオでは再現しうるが、そもそも初回接続すらできないため今回は未検証

## 使用性の評価根拠（5点満点中1点）
- 空状態やエラー時の文言自体（「読み込めませんでした」「通信できません。ネットワーク接続を確認してください。」＋再試行ボタン）はクラッシュや白紙よりはるかにマシで、単体で見れば悪くない設計
- しかし主要動線（お題に答える → タイムラインを見る → いいね/通報/ブロックする）が **1つも完走できない**。どれだけ待っても、再試行を押しても回復しない。ユーザー視点では「アプリが壊れている」としか見えない状態であり、採点基準の「1＝完走できない」に該当する

## 評価できなかったもの
- 受け入れ条件5（お題終了時刻を過ぎた投稿の非表示）、6の後半（通信回復後に通常画面へ戻れるか）、7（投稿等の失敗表示と再試行）: いずれも Supabase プロジェクトへ到達できないため、その手前の状態（起動直後の通信エラー）から先に進めず検証不能
- 受け入れ条件8（シードデータの非表示）: 画面自体に到達できないため「表示されない」ことを積極的には確認できていない（何も表示されないだけであり、意図した「他人の実回答が見える」という体験が達成されているわけではない）
- データ整合性（端末Bを削除して入れ直しても端末Aの回答が読めるか等）: サーバー操作が1件も成功しないため検証不能

## 次にすべきこと（提案）
1. まず `SupabaseConfig.swift` / `.env.local` に埋め込まれたプロジェクト参照・URLが正しいか、Supabaseダッシュボード（`supabase projects list` へのログイン、またはダッシュボードURLでの直接確認）で照合する。プロジェクトが実在するなら参照/URLの誤り、実在しないなら再作成とマイグレーション適用（`decorations` カラム追加を含む）が必要
2. 接続確認が取れたら、まず `xcodebuild -only-testing:SameQUITests` で既存の全 per-sprint テストを実行し、少なくとも自動化されている範囲で回帰が無いことを確認してから evaluator に引き渡す
3. その上で本評価の受け入れ条件1〜8を2台以上の実機/シミュレータで再検証する
