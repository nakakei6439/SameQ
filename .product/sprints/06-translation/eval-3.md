# スプリント 06 評価（attempt 3） — 判定保留（実機で評価不能）

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | **0/7 を実機で確認できず**（実機がロックされ、アプリを1度も操作できなかった） | 100% | 評価不能 |
| 2 安定性 | **評価不能**（attempt 2 の不合格理由「実機で2〜3件目で固着」を再現も否定もできていない） | クラッシュ0 / 主要動線完走 | 評価不能 |
| 3 データ整合性 | 評価不能（実機の `state.json` を1度も読めていない） | 100% | 評価不能 |
| 4 回帰 | シミュレータのフルスイート 90/90（`SameQTests` 57 ＋ `SameQUITests` 33）が全通過 | 100% | ✓（シミュレータのみ） |
| 5 使用性 | 評価不能 | 3以上 | 評価不能 |

**合否は出していない。** attempt 2 の不合格理由は「実機でのみ再現する固着」であり、
その再発有無を確かめられない以上、合格とは書けない。「たぶん直っている」で通さない。

---

## 検証環境と、実際にやったこと

- 対象: 作業ツリー（`HEAD` = `12b9ae2` ＋ 未コミットの `project.pbxproj`）
- 実機: iPhone 17 Pro Max / `B7121EA8-8AED-5E66-B696-511BFFC729E2`（`xcrun devicectl list devices` で `connected`）
- シミュレータ: iPhone 17 / `12050FBD-587B-4910-8812-696BB91BE051`
- 実施 2026-08-19 17:30〜18:20 JST

### できたこと
1. **実機向けビルド成功**（`xcodebuild -destination 'id=B7121EA8-…' -allowProvisioningUpdates build` → `** BUILD SUCCEEDED **`）
2. **実機へのインストール成功**（`xcrun devicectl device install app` → `App installed: bundleID: com.nakakei6439.SameQ`）
3. **17:32 の時点では1度だけ起動に成功した**（`devicectl device process launch` が通り、
   `devicectl device info processes` で `21605 …/SameQ.app/SameQ` を確認）。
   ただしこの時点では UI を駆動する準備（テストバンドルのビルド）がまだ終わっておらず、操作はしていない
4. **実機向けテストバンドルのビルド成功**（`build-for-testing` → `** TEST BUILD SUCCEEDED **`）
5. **シミュレータでフルスイートを単独実行 → 90/90 全通過**
   （`SameQTests` 57件 1.27秒 ／ `SameQUITests` 33件 1060.7秒、いずれも failures 0）

### できなかったこと（＝評価不能の理由）
**17:38 以降、実機が施錠されたままで、アプリを1度も操作できなかった。**

- `xcodebuild test -destination 'id=B7121EA8-…'` は、テストの1本目に入る前に失敗を繰り返す:
  ```
  Failed to start remote service "com.apple.mobile.notification_proxy" on device.
  … Code=-402653158 "The device is passcode protected."
  ```
  ログ 1680 行のうち `Test Case` の行は **0件**（テストが1本も始まっていない）
- `xcrun devicectl device process launch --device B7121EA8-… com.nakakei6439.SameQ` も:
  ```
  NSLocalizedFailureReason = Unable to launch com.nakakei6439.SameQ because the device was not, or could not be, unlocked.
  BSErrorCodeDescription = Locked
  ```
- 17:49〜18:18 の約30分、20秒間隔で起動を試み続けたが、**一度も解除されなかった**
  （`scratchpad/wait.log` に `locked <時刻>` が約80行）。17:32 に一度起動できているので、
  端末の自動ロックが掛かってそのままになったものと考えられる

---

## 次に実機確認を再開するために必要なこと（ユーザーへの依頼）

1. **iPhone 17 Pro Max のロックを解除する**
2. **自動ロックを一時的に「なし」にする**（設定 → 画面表示と明るさ → 自動ロック → なし）。
   D01（読み切りまでスワイプ）だけで数分かかり、既定の自動ロック時間だと**テストの途中で
   再施錠されて同じ失敗になる**。評価が終わったら元に戻してよい
3. 可能なら、受け入れ条件7の確認のために**機内モードのオン/オフ**をユーザー自身で切り替えてもらう
   （evaluator は端末設定を変更しない）

準備は済んでいるので、解除後は以下がそのまま流せる状態にしてある:

- 実機向けテストバンドルはビルド済み
  （`scratchpad/DDeval` に `-destination 'id=B7121EA8-…' build-for-testing` の成果物）
- evaluator 用の一時 XCUITest `SameQUITests/EvalSixDeviceTests.swift` を作成済み（未コミット。評価後に削除する）。
  `-SameQFakeTranslate` を**付けず**本物の Apple Translation を通す:
  - `testD01_realTranslationReadToExhaustionJA` — 端末そのまま（ja）で読み切りまでスワイプ。
    1件ごとに待ち時間・本文を記録し、60秒出なければ「固着」として失敗させる。
    ちらつき（表示直後と1.2秒後で本文が変わる）も検出する
  - `testD02_realTranslationReadToExhaustionEN` — `-AppleLanguages (en)` で同じことをする（お題の言語追従も見る）
  - `testD03_secondRunHasNoWait` — 1回目と2回目の起動で、お題確定・1件目表示までの秒数を比較（受け入れ条件4の後半）
  - `testD04_noTranslationUI` — お題（投稿前/後）・タイムライン・通報シートの全ラベルを列挙し、
    翻訳関連の文言が1つも無いことを確認（受け入れ条件2）
  - `testD05_regression` — 実機での回帰（未投稿時のタイムライン導線なし／空白のみの投稿の拒否／
    いいねの永続／ブロック一覧／BAN画面のボタン0個）

---

## 現時点で言えること・言えないこと

**言えること**
- コードはビルド・署名・インストールまで実機で問題なく通る
- シミュレータのフルスイート 90/90 は現在の作業ツリーでも全通過する（テストレベルでの回帰は無い）

**言えないこと（重要）**
- attempt 2 の不合格理由（実機で2〜3件目で無言のまま固着、3/3再現）が直ったかどうか。
  eval-2 で確認したとおり、この不具合は**シミュレータでは原理的に再現しない**
  （`-SameQFakeTranslate` は `sessionQueue` の手前で分岐するので、待ち行列と実セッションの
  協調部分を1行も通らない。シミュレータの実 Translation は全ペア `unsupported` を返す）。
  したがって「90/90 全通過」は、今回の修正が効いたことの証拠にまったくならない
- 受け入れ条件 1・3・4・5・6・7 の実機での成否
- 実機での安定性・データ整合性・使用性

## 評価できなかったもの
- 受け入れ条件 1〜7 のすべて（実機で1度もアプリを操作できていないため）
- 受け入れ条件4（翻訳モデル未取得時の初回表示）— 実機はモデル取得済みで未取得状態を作れない見込み。
  少なくとも「2回目以降に待ちが発生しない」側は D03 で測る用意がある
- 受け入れ条件7（機内モード）— 端末設定の変更にあたるため evaluator は実施しない
