# スプリント 12 評価（attempt 4） — 不合格

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 0/8 が観測で確認できた（server route はスキーマ不整合で最初の画面から進めない） | 100% | ✗ |
| 2 動作の安定性 | クラッシュ0・未処理例外0だが、Supabase経路の主要動線が1歩も完走できない。加えてLocalBackend既定経路でも「投稿後にタイムラインが開く」が3回連続で失敗 | 主要動線が最後まで通る | ✗ |
| 3 データ整合性 | サーバー操作がINSERT/SELECTとも成立しないため検証不能 | 100% | ✗ |
| 4 回帰 | Sprint01 3/5失敗・Sprint04 6/6失敗・Sprint11 5/5成功。抜き取り3件中2件で回帰を検出 | 100% | ✗ |
| 5 使用性の最低線 | Supabase経路は1（完走できない）。LocalBackend既定経路も投稿後にタイムラインへ進めず1に相当 | 3以上 | ✗ |

**5基準すべてが閾値未達で不合格。** 今回は2つの独立した問題が同時に見つかった。

1. **[本題] Supabase 経路のスキーマ不整合**: self-review（attempt 4）が「Supabase復活」を報告した内容自体は正しい（DNS解決・HTTP到達・認証通過をevaluatorも独立に再確認した）が、実際にアプリから`-SameQUseSupabaseBackend`で起動すると、`prompts`テーブルへのクエリが`column prompts.language does not exist`というサーバー側エラー（HTTP 400）で失敗し、起動直後の「読み込めませんでした」画面から一歩も進めない。self-review自身が「カラム構造の最終一致確認は service_role キーが要る」と書いていたリスクがそのまま的中した形。
2. **[evaluatorが新規に発見した regression] LocalBackend既定経路の破損**: sprint 12のコード変更とは無関係に見えるが、現在の日時（2026-08-26 19時台）でSprint01/04のUIテストを実行すると、オンボーディング完了→投稿までは成功するのに、投稿後に`timeline.card.body`（=自分以外の回答カード）が一度も出現しなくなっている。これはSprint01受け入れ条件5「投稿完了後に世界タイムラインが開き、自分以外のユーザーの回答が1件表示される」そのものの回帰であり、2台の異なるシミュレータ・3回の独立実行すべてで再現した安定した不具合。

## 検証環境
- 端末: iPhone 17 シミュレータ（`12050FBD-587B-4910-8812-696BB91BE051`, iOS 26.5）と iPhone 17 Pro シミュレータ（`4C9A260E-CC74-4DE6-AE65-509C6FC2F43E`, iOS 26.3）
- ビルド: `xcodegen generate` → `xcodebuild -project SameQ.xcodeproj -scheme SameQ -destination 'platform=iOS Simulator,name=iPhone 17' build`（BUILD SUCCEEDED）
- 実施時刻: 2026-08-26 18:52〜19:10 JST
- ネットワーク診断（evaluatorが独立に再実施、self-reviewの申告どおり到達可能なことを確認）:
  - `dig +short loqumzfgnahtclnvnrzb.supabase.co` → `172.64.149.246` / `104.18.38.10`（解決成功）
  - `curl` で6テーブル（posts/prompts/users/likes/reports/blocks）すべて `HTTP 200`・`body=[]`（データ空だが到達可能）を確認
- 自動テスト（evaluatorが自前で実機実行、self-reviewの申告を鵜呑みにせず再実行）:
  - `SameQTests`（ユニット）: 166/166 passed
  - `SprintOneAcceptanceTests`: 2/5 passed（3失敗、2回連続で同一の3件が失敗）
  - `SprintFourAcceptanceTests`: 0/6 passed（6件とも同一の原因で失敗）
  - `SprintElevenAcceptanceTests`: 5/5 passed

## 不合格の原因（これを直せば通る）

### [1] `-SameQUseSupabaseBackend` で起動すると `prompts.language` カラムが存在せず、起動直後から進めない
- **再現手順**:
  1. `xcodegen generate` → シミュレータ向けにビルド
  2. `xcrun simctl launch <device> com.nakakei6439.SameQ -SameQUseSupabaseBackend`
  3. 起動から数秒で画面が停止する
- **期待**: spec.md 306〜313行のとおり、今日のお題画面に到達し、投稿・タイムライン閲覧ができること
- **実際**: 「読み込めませんでした／サーバーでエラーが発生しました（column prompts.language does not exist）。」の画面で停止する。「もう一度試す」を押しても同じエラーになる（サーバー側のスキーマとクライアントのクエリが不一致なため、リトライしても物理的に成功しない）
- **根拠**: `/tmp/eval_supabase_A_1.png`（同内容を `.product/sprints/12-server-connection/evidence-attempt4-schema-error.png` として保存済み）。`xcrun simctl spawn <device> log show --predicate 'process == "SameQ"'` で該当リクエストが `HTTP 400` を返しているのも確認。self-review（attempt 4）の「自分で見つけた弱点 2」がまさにこの現象を予見していた

### [2] LocalBackend既定経路（引数なし通常起動）でも、投稿後に他人の回答が1件も表示されない（Sprint01 受け入れ条件5の回帰）
- **再現手順**:
  1. `xcrun simctl launch <device> com.nakakei6439.SameQ -SameQResetState`（または `xcodebuild -only-testing:SameQUITests/SprintOneAcceptanceTests test`）
  2. オンボーディングを完了（絵文字選択・ニックネーム入力・通知許可まで正常に進む）
  3. 今日のお題に回答して投稿する
- **期待**: spec.md 120行「お題画面で本文を入力して投稿すると、投稿完了後に世界タイムラインが開き、自分以外のユーザーの回答が1件表示される」
- **実際**: 投稿は成功する（クラッシュや通信エラーは出ない）が、`timeline.card.body`（他人の回答カード）が8秒待っても一度も出現しない。`SprintOneAcceptanceTests.test02_lockedUntilAnsweredThenTimeline`・`test03_likePersistsAcrossReopeningTimeline`・`test04_accountSurvivesRelaunch` の3件が同一箇所（`XCTAssertTrue failed - 投稿後にタイムラインが開く`）で失敗。`SprintFourAcceptanceTests` は通報・ブロック系6件全てが同じ「投稿後にタイムラインが開かない」で失敗（通報・ブロックの検証以前に、検証対象のカード自体が出現しない）
- **根拠**: 同一の失敗が、iPhone 17 とiPhone 17 Proの2台、および同一デバイスでの2回の独立再実行、計3回すべてで再現。ログ: `/tmp/sprint1_rerun.log:286`・`/tmp/sprint1_rerun2.log:286`（`SprintOneAcceptanceTests.swift:70`）、`/tmp/sprint4_single.log:207`（`SprintFourAcceptanceTests.swift:24`）。同時期に実行した`SprintElevenAcceptanceTests`は5/5成功しているため、テスト環境全体の不調（シミュレータ全滅など）ではなく、投稿後のタイムライン候補生成に絞って壊れていると考えられる
- **推測（根拠と分離）**: Sprint09で導入された自動お題生成・スケジュールの日次切り替わりが、たまたま evaluator の検証時刻（2026-08-26 19時台）に絡んで「今日のお題」の候補回答プール（`schedule.posts`）が空、または枯渇している可能性がある。eval-2（同日14:00〜14:17実施）では同じ`SprintOneAcceptanceTests`が5/5成功しているため、コード変更ではなく時刻依存の状態遷移が疑わしいが、これはevaluatorの推測であり、実際の原因特定と修正はgenerator側の作業。sprint 12自体のコード変更（BackendProviderへのコメント追加のみ）が原因ではないことは`git show d0bb42e -- SameQ/Backend/BackendProvider.swift`で確認済み

## 改善提案（合否には影響しない）
- self-review（attempt 4）の「動かし方」セクションに、`-SameQUseSupabaseBackend`使用時に事前にservice_roleキーでカラム構造を突き合わせる手順を追加すると、次回同種の事故（今回の[1]）を防げる
- [2]の再現性が高いことを踏まえ、`SprintOneAcceptanceTests`・`SprintFourAcceptanceTests`が「今日」の日付にどれだけ依存しているかをgenerator側で洗い出し、日付非依存のテストダブル（固定スケジュール注入）に切り替えることを検討すると、evaluatorの検証結果が実行時刻に左右されなくなる

## 評価できなかったもの
- spec.md 306〜313行の受け入れ条件1〜7は、[1]によりSupabase経路のオンボーディング画面より先に進めなかったため、いずれも実機で直接検証できなかった（self-reviewも同様に「検証不能」と自己申告しており一致する）
- 条件8（シードデータ非表示）はコード上の分岐（`BackendProvider.make()`がSupabase経路では`SeedCatalog`を呼ばない）は確認したが、[1]によりSupabase経路そのものが起動できないため実機での目視確認はできなかった

## 総評
self-review（attempt 4）の「Supabase復活」の報告自体は正確で、evaluatorも独立に同じ到達性を確認できた。ただしその先で自ら警告していた「カラム構造の不一致」が実際に起きており、Supabase経路は依然として起動画面から一歩も進めない。加えて、sprint 12の変更とは直接関係しない箇所で、Sprint01/04の中核動線（投稿後に他人の回答が表示される）が今回の検証時点で壊れていることを新たに検出した。5基準中5つすべてが閾値を下回っており、明確に不合格。次attemptでは（a）`prompts`テーブルのカラム名をクライアントのクエリに合わせる、または逆にクライアントのクエリをサーバーの実カラム名に合わせる、（b）LocalBackend既定経路で投稿後にタイムラインが開かない現象の原因（日付依存かどうか）を切り分ける、の両方に対応する必要がある。
