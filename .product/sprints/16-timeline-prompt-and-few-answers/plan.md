# スプリント 16: 世界タイムラインの見え方（お題の視認性、回答が少ないときの前向きな表示）

## 受け入れ条件（spec.md 行393〜401 から転記）
- [ ] 世界タイムライン上部のお題が、明るい表示・暗い表示のどちらでもはっきり読める（コントラスト 4.5:1 以上）
- [ ] 長いお題でも文字が見切れず全文が読める
- [ ] 未読の回答が3件未満のとき、前向きな案内が表示される
- [ ] 案内に数値が出ない
- [ ] 未読3件以上のときは案内が出ない
- [ ] 未読0件のとき既存表示と二重に出ない
- [ ] 案内が出ていてもスワイプ・いいね・通報・ブロックが効く
- [ ] 端末言語が英語のとき英語

## 実装方針

### F39（コントラスト・全文表示）
1. `Theme.swift` にプロンプト帯用の新しい背景 `promptStripBackground` を追加（白サーフェスに hairline の細い枠線）
2. `TimelineView.promptStrip` の背景を `Theme.hairline.opacity(0.35)` から新テーマに差し替え
3. お題本文の色を `Theme.inkSecondary` から `Theme.ink` に変更（白背景に対して ~14:1）
4. `lineLimit(2)` を撤去し、`fixedSize(horizontal: false, vertical: true)` のみで全文表示（長いお題も見切れない）
5. `Theme.contrastNote` 風の定数コメントで、計算したコントラスト比を self-review に残す

### F40（前向き案内）
1. `AppSession.swift` に `unreadTimelineCount: Int` 計算プロパティを追加（`timelineCandidateCount - timelineViewedCount`、最大0）
2. `TimelineView` の `body` で `timelineContent == .post && 1 <= unreadTimelineCount && unreadTimelineCount < 3` のときのみ `promptStrip` 直下に小さな案内テキストを差し込む
3. .empty / .exhausted / .loading のときは出さない（二重防止）
4. `L10n.Timeline` に `fewAnswersHint` を追加（en: "Not many answers yet. You might be one of the first." / ja: 「まだ回答が少ない。あなたが最初の一人かもしれない」）
5. 案内には数値・件数を含めない
6. 案内テキストは読み取り専用で、ジェスチャ・ボタンを覆わない配置（プロンプト帯とカードのあいだ、横幅フル・薄い文字色）

### テスト
1. `SprintSixteenAcceptanceTests.swift` を新規追加：0/1/2/3/5件ケースで案内の有無と既存表示の二重が出ないことを assert
2. `SameQTests/TimelineUnreadCountTests.swift` を新規追加：未読カウント計算のユニットテスト（`unreadTimelineCount` の負数ガード・候補0・候補3境目）

## 影響範囲
- `SameQ/Design/Theme.swift` に1〜2行追加（既存色定義を壊さない）
- `SameQ/Feature/Timeline/TimelineView.swift` の `promptStrip` と `body` のみ編集
- `SameQ/Session/AppSession.swift` に計算プロパティ1つ追加（既存挙動を壊さない）
- `SameQ/L10n.swift` に2文字列追加
- 既存UIテストの accessibilityIdentifier は変えない（`timeline.prompt` / `timeline.promptText` は維持）

## 触らないファイル
- 既存の `TodayPromptView.promptCard`（同じ配色変更を波及させない）
- `Backend` プロトコル・実装（カウントは AppSession 側だけで十分）
- Supabase / RevenueCat 関連
