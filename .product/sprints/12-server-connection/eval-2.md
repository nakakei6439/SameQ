# スプリント 12 評価（attempt 2） — 不合格

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 0/8 が観測で確認できた（残りはサーバー到達不能で検証不能） | 100% | ✗ |
| 2 動作の安定性 | クラッシュ0・未処理例外0だが、Supabase経路の主要動線が1歩も完走できない | 主要動線が最後まで通る | ✗ |
| 3 データ整合性 | サーバー操作が1件も成功しないため検証不能 | 100% | ✗ |
| 4 回帰 | Sprint01(5/5)・Sprint04(7/7)・Sprint05(7/7) 計19/19 passed | 100% | ✓ |
| 5 使用性の最低線 | Supabase経路は1（完走できない）。LocalBackend既定経路は問題なし | 3以上 | ✗ |

**5基準中3つが閾値未達で不合格。** 原因は attempt 1 と同一：アプリが接続する Supabase プロジェクト（`loqumzfgnahtclnvnrzb`）が evaluator の環境からも到達不能（DNS解決不能）であり、`-SameQUseSupabaseBackend` で明示的に接続を試みても起動直後の通信エラー画面から一歩も進めない。attempt 2 で対応が求められていた [2][3]（回帰修正・UIテスト実行）は実測で解消を確認したが、[1]（Supabase 到達不能）は今回も再現し、generator 側のコード変更では解決できない環境要因であることを独立に確認した。

## 検証環境
- 端末: iPhone 17 シミュレータ（`35AAC789-1DF1-4C51-B14D-94A5084F6B26`, iOS 26.5）と iPhone 17 Pro シミュレータ（`4C9A260E-CC74-4DE6-AE65-509C6FC2F43E`, iOS 26.3）、2台同時起動
- ビルド: `xcodegen generate` → `xcodebuild -project SameQ.xcodeproj -scheme SameQ -destination 'platform=iOS Simulator,name=iPhone 17' build`（BUILD SUCCEEDED）
- 起動A: 引数なし（既定 = LocalBackend、self-review.md記載の通常起動）
- 起動B: `-SameQUseSupabaseBackend`（self-review.md記載の「Supabase経路を試したい場合」の手順どおり）
- 実施時刻: 2026-08-26 14:00〜14:17 JST
- 自動テスト（evaluator が自前で実機実行、self-review.mdの申告を鵜呑みにせず再実行）:
  - `SprintOneAcceptanceTests`: 5/5 passed（106.6秒）
  - `SprintFourAcceptanceTests`: 7/7 passed（201.8秒）
  - `SprintFiveAcceptanceTests`: 7/7 passed（234.2秒）
- ネットワーク診断（evaluator が独立に再実施）:
  - `dig +short loqumzfgnahtclnvnrzb.supabase.co` → 応答なし（NXDOMAIN相当、解決不能）
  - `curl --max-time 10 https://loqumzfgnahtclnvnrzb.supabase.co/rest/v1/` → `curl: (6) Could not resolve host`
  - 対照として `curl https://supabase.com` → `200`、`dig aws-0-ap-northeast-1.pooler.supabase.com` → 正常に解決（ネットワーク全体やサンドボックス制限ではなく、このプロジェクト固有のホスト名だけが存在しないことを確認）
  - `supabase projects list` はCLI認証待ちと思われる状態で120秒応答なし（evaluatorに認証情報の付与がなく、プロジェクトの実在確認はこれ以上進められなかった）

## 不合格の原因（これを直せば通る）

### [1] Supabase プロジェクトが到達不能で、受け入れ条件1〜7がすべて検証不能（attempt 1 から変化なし・generator 側では修復不可）
- **再現手順**:
  1. `xcrun simctl launch <device> com.nakakei6439.SameQ -SameQUseSupabaseBackend` でSupabase経路を明示指定して起動
  2. 起動から数秒で「読み込めませんでした／通信できません。ネットワーク接続を確認してください。」の画面のまま停止（`/tmp/devB_supabase.png` を確認、`もう一度試す`ボタンあり）
- **期待**: spec.md 306〜312行のとおり、端末A・Bが同じお題に答え、互いの回答をタイムラインで読み、いいね・通報・ブロックが反映されること
- **実際**: オンボーディング後の通信を伴う画面に一切到達しない（既定のLocalBackend経路はオンボーディングまで正常に表示されるが、これはSupabaseに接続していないため本受け入れ条件の検証対象にならない）
- **根拠**: 独立したDNS解決失敗とcurl到達失敗（上記「検証環境」参照）。generatorが挙げた診断（`supabase migration list --linked` の tenant not found）と一致する原因系統
- **切り分け**: evaluator自身が対照ドメイン（`supabase.com`、Supabaseプーラーのホスト名）は正常に名前解決・到達できることを確認しており、evaluator環境のネットワーク制限ではなく、このプロジェクト参照 `loqumzfgnahtclnvnrzb` 固有の問題であることを再確認した

### [2] 受け入れ条件8も同様に検証不能
- Supabase経路のコードが `SeedCatalog` を呼ばない設計になっていることはコードレベルでは確認できるが、Supabaseサーバー自体に接続できないため「シードの代わりに実際に何が表示されるか」を画面上で確認することができない（画面が通信エラーで停止するのみ）

## 良かった点（attempt 1 の指摘への対応が確認できた）
- attempt 1 の eval-1.md [2]「既存UIテストが新既定のSupabaseBackendに乗って12件全滅」は解消。`BackendProvider.make()` の Debug 既定を `LocalBackend` に戻したことで、Sprint01/04/05 のUIテスト計19本がevaluatorの実機再実行で全て0 failuresだった（self-review.mdの申告どおりの結果を独立に再現できた）
- attempt 1 の eval-1.md [3]「既存UIテストを1本も実行せず引き渡した」も解消。self-review.mdに記載のテスト実行結果は誇張なく、evaluatorの再実行でも一致した

## 使用性の評価根拠（5点満点中1点、Supabase経路のみを対象に採点）
- 通信エラー画面の文言・再試行ボタン自体は妥当な設計（白紙・無限ローディング・クラッシュではない）
- しかし本スプリントが実現すべき主要動線（2台の端末で同じ世界を共有する）は、evaluatorの環境から1歩も進められない。ユーザー視点では「アプリが壊れている」としか見えない
- 参考: LocalBackend既定経路（本スプリントの検証対象ではない）はオンボーディングまで正常に表示され、evaluatorが単独で確認した限り見た目の破綻はない

## 評価できなかったもの
- 受け入れ条件1〜7のすべて、および8（Supabaseサーバー到達不能のため）
- データ整合性（端末Bを削除して入れ直しても端末Aの回答が読めるか等）
- スプリント06（端末内翻訳）の回帰、通信の遅さによるスワイプの引っかかり（いずれもサーバー到達が前提のため未確認）
- `supabase projects list` によるプロジェクト実在確認（CLI認証がevaluator環境に無く、120秒待っても応答がなかったため打ち切った）

## 改善提案（合否には影響しない）
- self-review.md 提案の「起動時にSupabaseへHEADリクエストを送り、失敗時はLocalBackendにフォールバック」は、本番運用でサーバーが不安定な際のユーザー体験を守る意味で妥当。ただし本スプリントの受け入れ条件（サーバーとの実データ共有）を検証する上では、evaluatorは明示フラグでSupabase経路を使い続ける必要がある
- ユーザー側の対応が必須: `https://supabase.com/dashboard/project/loqumzfgnahtclnvnrzb` へのログインでプロジェクトの現存・一時停止状態を確認し、必要なら再作成とマイグレーション（`supabase/migrations/20260819000004_server_connection.sql`）の再適用を行う。これはgenerator・evaluatorのいずれの権限でも実施できない

## 次にすべきこと
1. ユーザーがSupabaseダッシュボードにログインし、プロジェクト `loqumzfgnahtclnvnrzb` の状態（存在する／一時停止／削除済み）を確認する
2. 到達可能な状態に復旧してから、evaluatorが `-SameQUseSupabaseBackend` で2台のシミュレータを使い、受け入れ条件1〜8を再検証する
3. その際は本評価で実施した回帰確認（Sprint01/04/05のUIテスト）に加え、Sprint03・06も抜き取り対象に含めることを推奨（タイムライン取得ルールと翻訳はSupabase接続で最も壊れやすい領域のため）
