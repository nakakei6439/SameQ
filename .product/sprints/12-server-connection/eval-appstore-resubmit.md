# App Store 再提出前 検証 — オンボーディング完走確認（build 6 予定 / HEAD 無変更）

**判定: 合格（PASS）** — 401「セッションが切れました」は HEAD では再現しない。

## 判定サマリ
| # | 基準 | 結果 | 閾値 | 判定 |
|---|------|------|------|------|
| 1 | 受け入れ条件（今回のスコープ: オンボーディング完走・エラーalert無し・タイムライン到達） | iPhone/iPad × Allow/Later の4通りすべて完走 | 100% | ✓ |
| 2 | 動作の安定性 | クラッシュ0 / 未処理例外0 / 主要動線が最後まで通る。全ログで 4xx/5xx = 0（2xx: 200×317, 201×8, 204×9） | クラッシュ0 / エラー0 | ✓ |
| 3 | データ整合性 | 回答投稿→201→today.myAnswer 表示→アプリ完全再起動後も保持。匿名セッションも再起動後に維持（再オンボーディング無し） | 100% | ✓ |
| 4 | 回帰 | 回答投稿 / today.myAnswer 表示 / 再起動後の保持 / タイムライン起動＋空状態表示 の4点OK。「いいね」は他者回答が無く未実施（下記） | 100% | ✓（3件以上確認） |
| 5 | 使用性の最低線 | オンボーディングに進捗ドット・戻る・ブロッキングヒント（「同意すると次へ進めます」「絵文字を1つ選んでください」）。タイムライン空状態は意図的な文言。 | 3以上 | ✓（4） |

## 検証環境
- リポジトリ HEAD: `bf9f4d7`（branch main, v1.0.2 / CFBundleVersion 5）。**コード変更なし。**
- fix 3件は HEAD に在: `edb8f25`(tokenBox propagation), `8ad321a`(ensureFreshSession), `59ffdd9`(50分リフレッシュ) — `git show` で確認済み。
- ビルド: `xcodebuild -scheme SameQ -configuration Debug -sdk iphonesimulator` → **BUILD SUCCEEDED**。
- バックエンド: 本番 Supabase `loqumzfgnahtclnvnrzb.supabase.co`（`BackendProvider.make()` は Debug 既定で `SupabaseBackend`。`-SameQUseLocalBackend` 未指定）。onboarding 中に `https://loqumzfgnahtclnvnrzb.supabase.co/auth/v1/signup` 呼び出し→**201** をログで確認。
- 端末:
  - iPhone 17 Pro Max — iOS 26.5（UDID D20B56A3…）。fresh install（`simctl uninstall`＋`-SameQResetState`＋Maestro `clearState`）。Maestro で全自動。
  - iPad Air 11-inch (M4) — iOS 26.5（UDID 28AF11B2…）。fresh install。※アプリは iPhone 専用（`TARGETED_DEVICE_FAMILY=1`）のため iPad では iPhone 互換ウィンドウで動作。Maestro/XCTest が互換ウィンドウのアクセシビリティツリーを取得できないため、`cliclick` によるホスト座標クリック＋`simctl io screenshot` で手動走査。
- 実施時刻: 2026-09-04 06:43–07:06 JST。
- 検証データ: 当日の本番お題「この一年で、誰かに『変わりましたね』と言われたことはありますか？」。回答本文「eval regression check 2109」。
- ログ採取: `simctl spawn <udid> log stream --predicate 'processImagePath ENDSWITH "SameQ"'` を各ラン全区間。

## 実施した動線と結果

### オンボーディング完走（受け入れターゲット本体）
コンセプト → 利用規約（同意チェック）→ 絵文字選択 → ニックネーム（Allow版は空 / Later版は入力）→ 通知許可ステップ。
通知ステップで **2分岐を別々の fresh install で** 実施:

| 端末 | 分岐 | 通知ステップ後の到達先 | エラーalert | 401/4xx | 判定 |
|------|------|----------------------|-----------|---------|------|
| iPhone 17 Pro Max | 「通知を許可する」→OSダイアログ「許可」 | 今日のお題（today.input）到達。お題本文をサーバから取得表示 | 無し | 0（200×26, 201×2, 204×1） | PASS |
| iPhone 17 Pro Max | 「あとで設定する」 | 今日のお題到達 | 無し | 0（200×26, 201×2, 204×1） | PASS |
| iPad Air 11 (M4) | 「通知を許可する」→OSダイアログ「許可」 | 今日のお題到達（スクショ host_ipad15） | 無し | 0（200×42, 201×1, 204×2, 304×2） | PASS |
| iPad Air 11 (M4) | 「あとで設定する」 | 今日のお題到達（スクショ L_11） | 無し | 0（200×37, 201×1, 204×2, 304×2） | PASS |

- Apple がリジェクト理由に挙げた通知許可画面（「お題が届いたら お知らせします」）を4通りすべてで通過。`セッションが切れました` / `うまくいきませんでした` / `Something went wrong` の文言は Maestro `assertNotVisible` および目視でいずれも不在。
- 全ラン合計で **HTTP 401 は 0 件**、4xx/5xx は 0 件。匿名サインアップ（201）直後に認証必須リクエストが 200 で通っており、`edb8f25` の tokenBox 伝播が効いている。

### 回帰スイープ（基準4, iPhone 17 Pro Max）
1. **回答投稿** — today.input に入力 → 送信。バックエンドに **201 Created**（07:02:16 のログ 2件）。`today.myAnswer` に「eval regression check 2109」表示、「あなたの回答は確定しました」ロック表示（Maestro assertVisible 通過）。
2. **永続性** — `stopApp` → 再launch。アプリは前回画面（タイムライン）を復元し「このお題の回答はすべて読みました」= 回答済み状態をサーバから復元。タイムラインを閉じると `today.myAnswer` に同じ本文が残存（スクショ R7_persisted）。再オンボーディングは発生せず＝匿名セッション保持。
3. **タイムライン起動** — 「世界の回答を読む」で遷移。`世界の回答` が描画され、空状態「今は新しい回答がありません／このお題の回答はすべて読みました」を正しく表示。
4. **いいね** — 実施不可。単独テスターのため当該お題に他者の回答が 1 件も無く、いいね対象カード（`timeline.like`）が存在しない。データ都合であり不具合ではない。

### 安定性（基準2）
- アプリ起動 約10回 × 2端末でクラッシュ 0。`~/Library/Logs/DiagnosticReports` および各シミュレータの CrashReporter に 2026-09-04 付 SameQ クラッシュレポート無し。
- 全ログ横断で `fatal error` / `SIGABRT` / `Unexpectedly found nil` / `precondition failed` 等 0 件。

## 評価できなかったもの
- **iPad の全自動走査**: アプリが iPhone 専用バイナリのため iPad では iPhone 互換ウィンドウで動作し、Maestro/XCTest がそのウィンドウの要素ツリーを取得できない（`bounds [0,0][0,0]` の空ツリーを返す）。iPad は `cliclick` + スクリーンショット目視で1ステップずつ手動走査して完走を確認した。バイナリ・バックエンド経路は iPhone と同一（同じ `auth/v1/signup` 呼び出し→201 をログ確認済み）。
- **「いいね」回帰**: 他者回答が無く未実施（上記）。
- **通知許可の OS ダイアログ**: `simctl privacy grant notifications` が当環境で `Operation not permitted` のため事前付与できず、Allow 分岐では表示された OS ダイアログの「許可」を実タップして通した（iPhone は Maestro、iPad は cliclick）。

## 改善提案（合否に影響しない）
- （低）iPad 互換ウィンドウでの利用規約ステップ: 外側 ScrollView のスクロール余地が僅少で、同意チェックボックスがフッター（「同意すると次へ進めます」＋次へ）に一部隠れ、スクロールがラバーバンドで戻る。iPhone 実機では問題なし。iPhone 専用アプリを iPad 互換モードで開いた場合の見え方なので優先度は低いが、`.scrollBounceBehavior` やフッター高さの見直しで解消可能。
- （低）`simctl privacy grant notifications` が通らない環境向けに、UI テストで OS ダイアログを自動処理するヘルパー（Maestro の system dialog 対応 or `XCUIApplication` の interruption monitor）を整備しておくと再現検証が速くなる。

## 結論
HEAD（無変更）で、iPhone・iPad ともに、通知許可の Allow / Later 両分岐で、本番 Supabase に対しオンボーディングがクリーンに完走し、今日のお題画面へ到達する。Apple 2.1(a) リジェクトの `セッションが切れました`（HTTP 401 → `SupabaseError.unauthorized`）は **一度も再現しなかった**。build 6 としての再提出に対し、オンボーディング観点でのブロッカーは無い。
