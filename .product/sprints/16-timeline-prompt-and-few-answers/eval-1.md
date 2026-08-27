# スプリント 16 評価（attempt 1） — 合格

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 8/8 | 100% | ✓ |
| 2 安定性 | クラッシュ0 / 未処理エラー0 / 主要動線完走 | 0 | ✓ |
| 3 データ整合性 | 新規永続化なし・既存永続化は回帰で担保 | 100% | ✓ |
| 4 回帰 | 19/19（SprintThree 7 / SprintSix 4 / SprintFifteen 8） | 100% | ✓ |
| 5 使用性 | 4 | 3以上 | ✓ |

## 検証環境
- 端末: iPhone 17 シミュレータ / iOS 26.5（autoloop 既定）
- ビルド: `xcodebuild build-for-testing` → **TEST BUILD SUCCEEDED**（Debug）
- バックエンド: `-SameQUseLocalBackend`（サーバ非依存の表示ロジック検証）
- 使ったデータ: `-SameQAnswerCount 0/1/2/5`、`-SameQResetState`、`-SameQFakeTranslate`（英語カード表示用）、
  `-SameQTimeOffsetMinutes 22320`（カタログ最長のお題を今日のお題に出すため）、`-AppleLanguages (en)` / `-AppleInterfaceStyle Dark`
- 実施時刻: 2026-08-28 08:10〜08:35（JST）
- 証跡スクショ: `/tmp/sameq_eval16/*.png`（ja_oneAnswer / ja_zero_empty / ja_fiveAnswers[最長お題] / en_oneAnswer / dark_twoAnswers）
- 自動テスト: `SameQTests` 191/191、`SprintSixteenAcceptanceTests` 6/6、回帰 `SprintThree`/`SprintSix`/`SprintFifteen` 19/19
- 評価者が一時追加した XCUITest（スクショ＋ラベル採取用 5 本）は検証後に `git checkout` で除去済み。作業ツリー clean。

## 受け入れ条件の確認結果（すべて実操作で確認）

1. **お題の視認性・コントラスト 4.5:1 以上** — ✓
   お題表示帯の背景は `Theme.promptStripSurface = Theme.surface`（`Color.white` = #FFFFFF）、本文色は
   `Theme.ink`（`Color(red:0.129,green:0.145,blue:0.129)` ≈ #212521）。WCAG 相対輝度式で計算した
   コントラスト比 ≈ **15.5:1**（L_text≈0.0175, L_bg=1.0 →(1.05)/(0.0675)）。閾値 4.5:1 の 3 倍以上。
   ライト表示、および `-AppleInterfaceStyle Dark` を付けた OS ダーク状態の双方でスクショ目視。
   アプリは常時ライト描画のため、OS の外観設定に関わらず白帯＋黒文字で比は変わらない。
2. **長いお題でも全文が見切れず収まる** — ✓
   `PromptCatalog.candidatePool` 中で最長の「『なんでもない』と流したけれど本当は少し気になっていることを教えてください。」（37字）を
   今日のお題に出し、白帯が高さを自動で伸ばして全文（折り返し）を表示、省略記号なし（スクショ `ja_fiveAnswers.png`）。
   実装は `lineLimit(2)` を撤去し `fixedSize(horizontal:false, vertical:true)` のみ＝行数の上限が無い。
3. **未読3件未満で前向きな案内が出る** — ✓
   `-SameQAnswerCount 1` / `2` で、カード表示中に帯とカードのあいだへ
   「まだ回答が少ない。あなたが最初の一人かもしれない」（日本語）／「Not many answers yet. You might be one of the first.」（英語）が表示。
4. **案内に数値が出ない** — ✓ 文言に数字なし（`test02` が 0-9 を assert ＋ 目視）。件数・人数の表記も無し。
5. **未読3件以上で案内が出ない** — ✓ `-SameQAnswerCount 5` で帯直下に案内なし（スクショ `ja_fiveAnswers.png`）。
   `test04` が「残り3枚のあいだは非表示 → 残り2枚で初出現」の境界も緑。
6. **未読0件で二重表示にならない** — ✓
   `-SameQAnswerCount 0` は空状態「まだ誰も答えていません」＋補足1行のみ、案内は重ならない（スクショ `ja_zero_empty.png`）。
   読み切り後は「No new answers right now」相当のみで案内は消える（`test02`/`test03` が exhausted 時の非表示を assert）。
7. **案内表示中もスワイプ・いいね・通報/ブロックが効く** — ✓
   `test05`：ヒント表示中に `timeline.like` が hittable→タップで選択状態化、`timeline.more` が hittable、
   スワイプで読み切りまで到達。スクショでもヒントがカード／いいねボタンに被っていない。
8. **端末言語が英語のとき案内も英語** — ✓
   英語端末で案内・周辺UI（Close / THE WORLD'S ANSWERS / PROMPT / Like / Swipe to meet another stranger）すべて英語、
   見切れ・はみ出し・重なりなし（スクショ `en_oneAnswer.png`）。

**「少なさを謝る」文言チェック（評価者注記）**: 日本語・英語とも謝罪・欠落説明の語（申し訳ありません／まだ人が少なくて 等）は無く、
「最初の一人かもしれない」という前向きな転化になっている。→ 問題なし。

## 安定性・回帰・データ整合性
- クラッシュ 0、未処理例外 0。約 12 回のテスト実行＋手動起動で異常終了なし。
- 回帰: `SprintThreeAcceptanceTests` 7/7（タイムライン中核：重複なしスワイプ、既読の再表示防止＝再起動後も維持、空状態、単一→読み切り、先頭ランダム、戻る動線なし、今日のお題のみ）、
  `SprintSixAcceptanceTests` 4/4（翻訳・お題帯を多用）、`SprintFifteenAcceptanceTests` 8/8（多言語表示）。計 19/19。
- データ整合性: 本スプリントの変更は表示ロジックのみ（`Theme` 定数追加、`TimelineView` の帯配色＋案内分岐、
  `AppSession.unreadTimelineCount` 計算プロパティ、`L10n` 2文字列）。新規の永続化フィールドは無し。
  `unreadTimelineCount` は既存の `timelineCandidateCount`/`timelineViewedCount` から都度計算。
  `replaceTimelineCountsForTest` は `#if DEBUG` のユニットテスト専用で本番経路から呼ばれない。
  既読の永続化そのものは SprintThree 回帰（再起動後も既読が戻らない）で担保。

## 改善提案（合否には影響しない）
- **[中] 5件など「多め」のタイムライン終盤で案内が再出現する**：`-SameQAnswerCount 5` で読み進めると
  残り2枚・1枚（`unread+現在カード` が 2/1）に入った時点で「まだ回答が少ない。あなたが最初の一人かもしれない」が再び出る。
  既に4人の回答を読んだ後に出るので軽い違和感がある。spec の条件（未読3件以上で非表示）には抵触しないが、
  「タイムラインを開いた時点で少ない日」に限定する（開いた直後の総候補数で判定する等）と意図に近くなる。
- **[低] 「暗い表示モード」は実質ダークテーマ非対応**：アプリは常時ライト描画。コントラスト比は維持されるため
  条件1は満たすが、OS ダーク時に白帯が眩しいと感じる余地はある。全体テーマ改修としてバックログ化推奨（F39 スコープ外）。
- **[低] 案内が出ていないときの余白**：お題帯とカードのあいだの縦スペースが、案内ありのときの高さを見越してか
  やや広く空いて見える瞬間がある。

## 評価できなかったもの
- なし（受け入れ条件8項目すべて実機シミュレータ操作で確認した）。
- 物理的なダークモード端末での実地目視はシミュレータで代替（アプリがライト固定のため描画は同一）。
