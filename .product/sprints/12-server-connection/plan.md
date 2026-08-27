# スプリント12 attempt 9 計画

## 状況
attempt 8 が autoloop.sh の3時間タイムアウトで SIGTERM 強制終了。コード変更は完了・コミット済みだが、
絞り込みUI回帰テストが完走しなかった（attempt 8 self-review に「UI回帰: 未完了」と記載）。
attempt 8 完了済みコード変更:
- `BackendProvider.make()` の Debug 既定を SupabaseBackend に1行戻し
- `LaunchOptions` の `-SameQUseSupabaseBackend` → `-SameQUseLocalBackend` 反転
- 11個のUIテストファイルに `-SameQUseLocalBackend` 注入
- `SprintTwelveAcceptanceTests.swift` 新規追加（test01〜test03）

## 受け入れ条件（spec.md 305〜313行、attempt 8 自己評価から転記）
- [ ] 1〜7 は seed 投入済み Supabase プロジェクトに対する実機2台検証が必要 → evaluator 担当
- [ ] 8 シード非表示: Debug 既定 SupabaseBackend + Release 無条件 SupabaseBackend 経路で seed が漏れないこと
- [ ] generator 側で担保する土台: BackendProvider 切替・`-SameQUseLocalBackend` 注入・SprintTwelve 追加

## attempt 9 でやること
1. コード変更は attempt 8 のものをそのまま使う（巻き戻し不要）
2. **絞り込みUI回帰テストを実行**（generator.md 指示に従い、全件でなく最大4クラス）
   - SprintTwelveAcceptanceTests（全3件・必須）
   - 直近スプリントの固定サンプル3クラス: SprintElevenAcceptanceTests / SprintTenAcceptanceTests / SprintNineAcceptanceTests
3. ユニットテストは前回 attempt 8 で 166/166 成功を確認済み。再実行して再確認
4. self-review.md を書き、state.json を awaiting_eval に更新

## 影響範囲
なし（attempt 8 のコード変更はすでにコミット済みで、attempt 9 はテスト実行のみ）
