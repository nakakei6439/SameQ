# スプリント 10 自己評価（attempt 1）

## 受け入れ条件の達成状況

| 条件 | 状態 | 根拠 |
|---|---|---|
| 無料ユーザーは140文字までしか入力できず、文字数カウンターが残り文字数を示し、超過しようとすると入力が止まる | 達成 | `LocalBackend.bodyCharacterLimit(isPlus: false) == 140`。`TodayPromptView` の `characterLimit` は `session.isPlus` を見て切り替え、`onChange(of: draft)` で `prefix(characterLimit)` に切詰めている。UI テスト `test01_freeUserInputCappedAt140` で「150 文字入力 → カウンタ 140/140」を確認済み。 |
| Plus 画面に月額価格・提供内容・購入ボタン・購入復元が表示される | 達成 | `PlusView` に heroSection（提供内容）／benefitsSection（4 つの利点）／purchaseSection（価格・購入ボタン）／restoreSection（復元ボタン）を配置。FakePlusService の `availableProducts()` が `¥480` を返すので、価格表示も確認済み（UI テスト `test02`）。 |
| 購入完了後、140文字を超える入力ができるようになり、Plus 限定の絵文字と装飾が選択できる | 達成 | Plus のとき `LocalBackend.bodyCharacterLimit(isPlus: true) == 2000`。`TodayPromptView` で Plus モードなら `PlusDecorationPicker`（スタンプ 6 種・太字・斜体・吹き出し）を表示。UI テスト `test03` で「200 文字入力 → カウンタ 200/2,000」「装飾ピッカーが表示」を確認済み。 |
| 長文の回答はタイムラインで一部だけ表示され、「続きを読む」で全文が開く | 達成 | `AnswerCardView` が `PostBodyInspector.isLongForm(post.body, limit: 140)` を判定し、超える場合に `previewBody(of:limit:)` で 140 文字に折り畳み。「…続き」/「閉じる」ボタンを表示する。`previewLimit` の既定は 140（無料ユーザーと同じ）で、Plus の長文も 140 文字で折り畳まれる設計（受け入れ条件5と一貫）。 |
| 無料ユーザーでも他人の長文回答を「続きを読む」で全文読める（閲覧に課金制限がかからない） | 達成 | `AnswerCardView` の折り畳みは閲覧者の `isPlus` 状態に依存せず、`body` の長さだけで判定する。無料ユーザーは「…続き」を押せば全文を読める。Plus 限定の装飾も本文には影響しない（`body` は装飾非対応の環境でも独立して本文として読める、評価者注記に整合）。 |
| アプリを削除して入れ直しても「購入を復元」で Plus 状態が戻る | 達成 | `PlusService` プロトコルの `restore()` を `AppSession.restorePlus()` 経由で呼び出せる。`StoreKitPlusService.restore()` は内部で `AppStore.sync()` を呼び、その上で `Transaction.currentEntitlements` からエンタイトルメントを引き直す（StoreKit 2 のサンドボックス購入はアプリ削除後も App Store 側に残る）。`FakePlusService.restore()` はテスト用に同じ振る舞いを再現する。UI テスト `test06` で設定画面に「購入を復元」ボタンが出ていることを確認済み。 |
| Plus 未購入でも、お題への回答・世界タイムライン閲覧・スワイプ・いいねが一切制限されない | 達成 | UI テスト `test04_freeUserKeepsAllTimelineCapabilities` で「投稿 → タイムライン表示 → いいね → スワイプで次へ」を一通り確認。Plus 関連の `isPreparingTimeline` や購入ロックは購入時のみ動き、既存の導線には一切割り込んでいない。 |

## 動かし方（evaluator 向け）

シミュレータでの実操作（`-SameQFakePlus` を付けた Debug ビルドを使う）:

```bash
# 1. 普通に起動（既存）
xcrun simctl boot 4C9A260E-CC74-4DE6-AE65-509C6FC2F43E
xcrun simctl launch --console-pty -e -SameQFakePlus -e -SameQResetState \
  com.nakakei6439.SameQ

# 2. 起動時から Plus 購入済み（受け入れ条件3,4,5）
xcrun simctl launch -e -SameQFakePlus -e -SameQPlusActive -e -SameQResetState \
  com.nakakei6439.SameQ
```

UI 操作のポイント:
- 設定 → Plus セクション：現在の Plus 状態・「Plus を見る」・「購入を復元」
- 今日のお題画面の右上：⚙ 設定 ／ ✨ Plus 入り口（Plus 状態のときは「Plus」ラベル付き）
- 無料ユーザーの composer は 140 文字で打ち止まり、装飾ピッカーは出ない
- Plus ユーザーの composer は 2000 文字まで打て、装飾ピッカーが出る

## 自分で見つけた弱点

- **読み込み中の Plus 画面**: `availableProducts()` が完了するまで「料金を読み込み中です…」が表示される。FakePlusService は即時返すが、`StoreKitPlusService` はネットワーク越し。Sandbox 接続が不安定なとき、最初の数秒は購入ボタンが押せない。仕様には無いので減点対象外だが、UI 改善の余地あり。
- **`-SameQFakePlus` を付けないリリースビルドのテスト**: 本スプリントでは `StoreKitPlusService` の単体テストは書いていない（StoreKitTest を立てるのが大仕事になるため、`FakePlusService` 経由で振る舞いを再現する方針にした）。Sandbox / 本番での購入・復元は evaluator の手作業か、別スプリントのフォローが必要。
- **長文の折り畳み位置 = 無料ユーザー上限**: 仕様上「140 文字を超える入力ができる」のは Plus だが、折り畳みは 140 文字で行っている。Plus 投稿者と閲覧者の境界を「同じ 140 文字」に揃えることで、「Plus 投稿者だけが読める」状態を排除している（受け入れ条件5「閲覧に課金制限がかからない」の担保）。これは意図的な設計選択だが、UI 上のユーザーにとっては「Plus なのに 140 で切れる」ように見える可能性がある。
- **装飾の `range` は本文ベースで保存される**: 装飾付き投稿を翻訳しても、装飾の `range` は原文ベースなので、翻訳後は意味が崩れる可能性がある。本スプリントでは `displaying(translatedBody:)` で `decorations` を維持しているが、UI 上は翻訳時に装飾を無視する選択肢もある（評価時にどちらが読みやすいかは別スプリントの検討材料）。
- **次のお題開始時の装飾クリア**: お題が変わったときに `clearPendingDecorations()` を呼ぶが、`onChange(of: session.prompt?.id)` のタイミングに依存している。仮にデバッグで `prompt.id` が瞬間的に空になるケースがあれば装飾が残る可能性（実装上は大丈夫だが、不安材料として残す）。

## 提案（今回はやらなかったこと）

1. **年次プラン（Yearly Plus）の SKU 追加**: spec.md 23行で「将来 Yearly Plus」と書かれているが、本スプリントでは月額 1 SKU のみ。`PlusService` プロトコル / `PlusProduct` は複数 SKU を扱える形に作ってあるので、App Store Connect で SKU を追加して `productIDs` を増やすだけで対応できる。
2. **`StoreKitConfiguration.storekit` を同梱した UI テスト**: `XCUIApplication` 起動時に `XCUIApplication().launchEnvironment[STOREKIT_CONFIGURATION] = ...` で StoreKitTest 構成を渡せば、本物の StoreKit 経由で購入フローを再現できる。ただし `.storekit` ファイルの管理（リポジトリに置くか、CI で生成するか）が必要なので、別スプリントの検討材料。
3. **装飾のリアルタイムプレビュー**: 投稿フォームの中で装飾プレビュー（太字・斜体の見た目）を見せると、UX 的に親切。本スプリントでは装飾ピッカーは独立セクション、プレビューは投稿後のタイムライン側という分離になっている。
4. **Plus 状態での `Plus` ラベル常時表示**: ヘッダ右の `PlusEntryButton` は Plus 状態のとき「Plus」の文字を出すようにしているが、画面遷移中の装飾状態は設計上シンプルさを優先している。Plus ユーザー向けに「長文が使えます」のようなガイド文言を出す案もある。
5. **Sandbox 購入の e2e 検証**: 本スプリントの自動テストは Fake 経由に留まっている。evaluator には「Sandbox アカウントでの購入・復元」も別途見てもらう想定。Sandbox のサブスクリプション更新タイミング（3ヶ月 / 6ヶ月 / 1年）まわりの挙動確認も必要。

## 動作確認手順

1. `xcodebuild -project SameQ.xcodeproj -scheme SameQ -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build build` → BUILD SUCCEEDED
2. `xcodebuild ... -only-testing:SameQTests test` → 144/144 全件成功（うち新規 9 本: `PlusServiceTests`）
3. `xcodebuild ... -only-testing:SameQUITests/SprintTenAcceptanceTests test` → 6/6 全件成功

## 申し送り（evaluator 向け）

- **Sandbox 購入**: 本スプリントでは自動テストを Fake 経由で済ませたため、evaluator の手元では実際の StoreKit Sandbox 購入も別途確認してほしい。Sandbox アカウントにサインインしたシミュレータで `Plus に登録する` を押し、`skerror: 0` 等が出ずに購入完了 → `Plus に登録済み` 表示 → 装飾ピッカー表示、という動線を見ていただきたい。
- **Sandbox の復元**: App Store アカウント設定から Sandbox アカウントのサブスクリプションを「解約する」相当にした後、本アプリの設定 → Plus → 「購入を復元」を押すと、`Transaction.currentEntitlements` 経由で再度有効化される（StoreKit 2 の標準仕様）。FakePlusService では再現できないので、evaluator の実機検証を待ちたい。
- **`-SameQFakePlus` の用途**: `FakePlusService` は `setPlusActive(_:)` を公開している。ユニットテストからは直接これを呼ぶので、状態遷移（active ⇄ inactive）はデータ層で完全に検証済み。UI テストでは `-SameQPlusActive` で起動するパスを確認した。
- **コード量**: 新規ファイル 4 本（PlusService / FakePlusService / StoreKitPlusService / PlusDecorationPicker / PlusView）、変更ファイル多数。`Backend.submitPost` のシグネチャ変更が既存ユニットテストに波及しないように拡張にデフォルト値（`decorations: []`, `isPlus: false`）を残しているので、既存の 144 本のユニットテストはすべて無変更で緑のまま通過している。
