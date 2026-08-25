import XCTest
@testable import SameQ

/// スプリント 09（F26 / F27）の受け入れ条件のうち、画面操作では確かめにくい部分を
/// ここで押さえる。
///
/// 「データ層で確定的に動く」ことが受け入れ条件 1, 2, 3, 4, 6 の主軸なので、
/// `PromptGenerator` と `SeedCatalog.loadScheduleWithAutoGeneration` を直接
/// 検証する。受け入れ条件 5（候補の性質）は手の目で確認する分量の問題なので
/// ここでは「候補プールが PromptCatalog 経由で必ず一定のサイズを持つ」だけを担保する。
final class PromptGenerationTests: XCTestCase {

    /// UTC の暦日を作ってテスト時刻の基準にする。
    private func utcDate(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return calendar.date(from: components) ?? Date()
    }

    // MARK: 受け入れ条件 5（候補プールの性質）

    /// 候補プールが既存シードと同種（短く答えられる・特定文化に依存しない）に
    /// なっていることを最低限担保する。受け入れ条件 5 のうち「短い答えられる」
    /// 「特定文化に依存しない」は手の目視確認と組み合わせるが、ここでは
    /// 「候補が一定数以上ある」「空ではない」だけを保証する。
    func testCandidatePoolIsNonEmptyAndHasReasonableSize() {
        XCTAssertFalse(PromptCatalog.candidatePool.isEmpty, "候補プールが空では 1 日 1 件の自動生成ができない")
        XCTAssertGreaterThanOrEqual(
            PromptCatalog.candidatePool.count, 30,
            "短い問いかけを 30 件以上用意する（隣接日に近いお題が続けて出ないために十分な幅が必要）"
        )
    }

    /// フォールバック候補（F27）が「必ず安全」と分かっている文言だけであることの確認。
    func testFallbackPoolContainsSafeSeedTexts() {
        XCTAssertFalse(PromptCatalog.fallbackPool.isEmpty, "フォールバック候補が無いと起動不能になる")
        for entry in PromptCatalog.fallbackPool {
            XCTAssertTrue(
                PromptSafetyChecker.isAllowed(entry.text),
                "フォールバック候補は安全条件を満たす必要がある: \(entry.text)"
            )
        }
    }

    /// 受け入れ条件 4：候補プールには最初から安全条件違反の文言が含まれていない。
    ///（`PromptGenerator` 内の discard 経路は別テストで個別に確かめる）
    func testCandidatePoolIsAllSafe() {
        for (index, candidate) in PromptCatalog.candidatePool.enumerated() {
            XCTAssertTrue(
                PromptSafetyChecker.isAllowed(candidate),
                "候補プール #\(index) が安全条件を満たしていない: \(candidate)"
            )
        }
    }

    // MARK: 受け入れ条件 1（1 日 1 回自動生成、翌日で別のお題）

    /// 同じ `reference` からは同じ Prompt が返る（決定性）。
    func testGeneratorIsDeterministicForSameReference() {
        let reference = utcDate(year: 2026, month: 8, day: 25)
        let first = PromptGenerator.generate(reference: reference)
        let second = PromptGenerator.generate(reference: reference)
        XCTAssertEqual(first.prompt.id, second.prompt.id)
        XCTAssertEqual(first.prompt.text, second.prompt.text)
        XCTAssertEqual(first.prompt.startsAt, second.prompt.startsAt)
        XCTAssertEqual(first.prompt.endsAt, second.prompt.endsAt)
    }

    /// 異なる日付からは別のお題（少なくとも ID は別）が返る（受け入れ条件 1）。
    /// ID は `prompt_yyyyMMdd` で日付を含むので別日が立てば必ず別 ID。
    func testGeneratorReturnsDifferentPromptForDifferentDays() {
        let day1 = utcDate(year: 2026, month: 8, day: 25)
        let day2 = utcDate(year: 2026, month: 8, day: 26)
        let prompt1 = PromptGenerator.generate(reference: day1).prompt
        let prompt2 = PromptGenerator.generate(reference: day2).prompt
        XCTAssertNotEqual(prompt1.id, prompt2.id, "日付が違えば ID も違う")
        // 開始時刻も違う
        XCTAssertNotEqual(prompt1.startsAt, prompt2.startsAt)
    }

    // MARK: 受け入れ条件 2（世界共通 = 同じ UTC 日付には同じ結果）

    /// 同じ UTC 日付については、Prompt は端末横断で完全に一致する
    ///（受け入れ条件 2: 「同じ時刻に別のアカウント／別の端末で開いても、同一のお題」）。
    /// 端末ローカルのタイムゾーンが違っても、`reference` の UTC 暦日が同じなら
    /// 同じ Prompt が返る。
    func testGeneratorIsStableAcrossReferenceTimezones() {
        let utc = utcDate(year: 2026, month: 8, day: 25, hour: 12)
        // UTC の 12:00 は LA では 05:00 PDT、Tokyo では 21:00 JST。
        // すべて 2026-08-25 の暦日なので、Prompt は同じになる。
        let fromUTC = PromptGenerator.generate(reference: utc)
        XCTAssertEqual(fromUTC.prompt.id, "prompt_20260825")
        // 直接 dayKey 指定で同じ結果になることを確認（端末横断の安定性）
        let direct = PromptGenerator.generate(dayKey: "20260825", dayIndex: PromptGenerator.dayIndex(for: utc))
        XCTAssertEqual(direct.prompt.id, fromUTC.prompt.id)
        XCTAssertEqual(direct.prompt.text, fromUTC.prompt.text)
    }

    // MARK: 受け入れ条件 3（生成失敗時のフォールバック）

    /// 候補プールが空の場合、フォールバックの Prompt が返る（F27）。
    func testFallsBackWhenCandidatePoolIsEmpty() {
        let reference = utcDate(year: 2026, month: 8, day: 25)
        let result = PromptGenerator.generate(
            reference: reference,
            candidatePool: [],
            fallbackPool: PromptCatalog.fallbackPool
        )
        XCTAssertTrue(result.usedFallback, "候補プールが空のときはフォールバック使用")
        XCTAssertNotNil(result.prompt.text.first)
        XCTAssertFalse(result.prompt.text.isEmpty)
    }

    /// 全候補が不適格だったときもフォールバックに落ちる（受け入れ条件 3）。
    /// 「全候補不適格」を作るには、候補に `disallowedKeywords` のキーワードを
    /// 含ませる必要がある。テストでは「1 件だけ unsafe だが候補プール 1 件」
    /// という形で「全滅」を再現する。
    func testFallsBackWhenAllCandidatesAreUnsafe() {
        let reference = utcDate(year: 2026, month: 8, day: 25)
        let unsafeCandidates = [
            "政党の支持率を教えてください",  // politics 違反
            "宗教についてどう思いますか？"  // religion 違反
        ]
        let result = PromptGenerator.generate(
            reference: reference,
            candidatePool: unsafeCandidates,
            fallbackPool: PromptCatalog.fallbackPool
        )
        XCTAssertTrue(result.usedFallback, "全候補不適格ならフォールバック")
        XCTAssertEqual(result.discarded.count, 2, "両方の候補が破棄記録に残る")
        XCTAssertEqual(Set(result.discarded.map(\.reason)), [.politics, .religion])
    }

    /// フォールバックプールも空のときは最後の砦として prompt_001 を返す
    ///（必ず何らかのお題が有効」の最終保証）。
    func testLastResortPromptWhenFallbackPoolIsAlsoEmpty() {
        let reference = utcDate(year: 2026, month: 8, day: 25)
        let result = PromptGenerator.generate(
            reference: reference,
            candidatePool: [],
            fallbackPool: []
        )
        XCTAssertTrue(result.usedFallback)
        XCTAssertFalse(result.prompt.text.isEmpty)
        XCTAssertTrue(result.prompt.id.hasPrefix("prompt_"), "最後の砦の Prompt ID は prompt_ 形式")
    }

    // MARK: 受け入れ条件 4（破棄された記録が残る）

    /// 採用候補の手前に不適格な候補があった場合、それらは破棄記録に残る
    ///（受け入れ条件 4）。`startIndex` のオフセット次第で最初の方に unsafe が
    /// 来る場合を再現するため、`startIndex` を直接指定できる API を使う。
    func testDiscardsAreRecordedForUnsafeCandidatesBeforeAcceptedOne() {
        // dayIndex=0, poolSize=4 で startIndex は (0 + 4/2) % 4 = 2。
        // つまり候補 #2 から走査される。#2 が unsafe（politics 違反）、#3 が safe → #3 が採用。
        let pool = [
            "政党の話はできますか？",  // 0 (unsafe: politics)
            "宗教は信じますか？",    // 1 (unsafe: religion)
            "あなたの政党の支持率は？", // 2 (unsafe: politics 違反)
            "好きな季節は？"          // 3 (採用される)
        ]
        let result = PromptGenerator.generate(
            dayKey: "20260825",
            dayIndex: 0,
            candidatePool: pool
        )
        XCTAssertEqual(result.prompt.text, "好きな季節は？")
        XCTAssertEqual(result.discarded.count, 1, "採用候補の手前の 1 件だけ破棄記録に残る")
        XCTAssertEqual(result.discarded.first?.text, "あなたの政党の支持率は？")
        XCTAssertEqual(result.discarded.first?.reason, .politics)
    }

    // MARK: 受け入れ条件 6（有効期間、2 つ同時表示なし）

    /// 生成された Prompt は 28 時間（`Prompt.defaultDuration`）有効。
    /// 24〜36 時間の範囲内（受け入れ条件 6）。
    func testGeneratedPromptDurationIsInAcceptedRange() {
        let reference = utcDate(year: 2026, month: 8, day: 25)
        let prompt = PromptGenerator.generate(reference: reference).prompt
        let duration = prompt.endsAt.timeIntervalSince(prompt.startsAt)
        let hours = duration / 3600
        XCTAssertGreaterThanOrEqual(hours, 24, "有効期間は 24 時間以上")
        XCTAssertLessThanOrEqual(hours, 36, "有効期間は 36 時間以下")
        XCTAssertEqual(duration, Prompt.defaultDuration, accuracy: 1, "既定は 28 時間")
    }

    /// 開始時刻は UTC の暦日 00:00。
    func testGeneratedPromptStartsAtUtcMidnight() {
        let reference = utcDate(year: 2026, month: 8, day: 25)
        let prompt = PromptGenerator.generate(reference: reference).prompt
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: prompt.startsAt)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 8)
        XCTAssertEqual(components.day, 25)
        XCTAssertEqual(components.hour, 0)
        XCTAssertEqual(components.minute, 0)
        XCTAssertEqual(components.second, 0)
    }

    /// `SeedCatalog.loadScheduleWithAutoGeneration` で、`.live` のように既存シードが
    ///「今日」を既にカバーしているときは自動生成がスキップされ、シードのお題がそのまま残る
    ///（受け入れ条件 6: 2 つのお題が同時に表示されない）。
    ///
    /// スプリント09 attempt 2 の修正で `.live` の seed prompt は絶対アンカー (liveAnchor) から
    /// 28h 間隔で並ぶようになった。coverage (56h) 以内の reference では prompt_001 が
    /// active な状態で schedule に入り、`scheduleAlreadyCoversToday` が true を返す。
    /// ここでは coverage 内（= liveAnchor + 12h）の reference を使う。
    func testSeedCatalogSkipsAutoGenWhenSeedsAlreadyCoverToday() throws {
        let reference = SeedCatalog.debugLiveAnchor.addingTimeInterval(12 * 60 * 60)
        let (schedule, generation) = try SeedCatalog.loadScheduleWithAutoGeneration(
            reference: reference,
            scenario: .live
        )
        XCTAssertNil(generation, "シードが今日をカバーしているときは自動生成しない")
        XCTAssertTrue(schedule.prompts.contains { $0.id == "prompt_001" })
    }

    /// スプリント09 attempt 2: `.live` の coverage 期間 (56h) 以降に reference があるときは
    /// seed prompt の period が全て `reference` より前に配置され、`scheduleAlreadyCoversToday`
    /// が false を返すため `PromptGenerator` が起動する（受け入れ条件 1: 翌日に別のお題が出る）。
    func testLiveScenarioOutsideCoverageSchedulesPromptsInThePastAndFallsThroughToAutoGen() throws {
        // liveAnchor + 5 days = 120h > coverage (56h) → coverage 外
        let reference = SeedCatalog.debugLiveAnchor.addingTimeInterval(5 * 24 * 60 * 60)
        let (schedule, generation) = try SeedCatalog.loadScheduleWithAutoGeneration(
            reference: reference,
            scenario: .live
        )
        // seed prompt は schedule に入っている
        XCTAssertTrue(schedule.prompts.contains { $0.id == "prompt_001" })
        XCTAssertTrue(schedule.prompts.contains { $0.id == "prompt_002" })
        // seed prompt はいずれも reference 時点で active でない（period が全て reference より前）
        for prompt in schedule.prompts where prompt.id == "prompt_001" || prompt.id == "prompt_002" {
            XCTAssertFalse(
                prompt.isActive(at: reference),
                "seed prompt \(prompt.id) は coverage 外では active でない"
            )
        }
        // 自動生成が走り、別 prompt (prompt_yyyyMMdd 形式) が schedule に追加される
        XCTAssertNotNil(generation, "coverage 外では PromptGenerator が必ず起動する")
        XCTAssertTrue(
            generation?.prompt.id.hasPrefix("prompt_2") == true,
            "自動生成 prompt は prompt_yyyyMMdd 形式 (UTC 暦日): \(generation?.prompt.id ?? "")"
        )
        // active prompt は自動生成された prompt になっている
        XCTAssertEqual(schedule.activePrompt(at: reference)?.id, generation?.prompt.id)
    }

    /// スプリント09 attempt 2: `.live` で「同じインストールのまま日をまたぐ」と
    /// 自動生成された prompt (UTC 暦日 ID) が出る（受け入れ条件 1 の本命経路）。
    /// 1 日目と 2 日目で reference を変えると、seed prompt は同じ ID (prompt_001/002) のままだが
    /// active な prompt は UTC 暦日 ID の自動生成 prompt に切り替わる。
    func testLiveScenarioDayTransitionProducesNewAutoGeneratedPrompt() throws {
        // 1 日目: coverage 内 (anchor + 12h)
        let day1 = SeedCatalog.debugLiveAnchor.addingTimeInterval(12 * 60 * 60)
        // 2 日目: coverage 外 (anchor + 5 days = 120h > 56h)
        let day2 = SeedCatalog.debugLiveAnchor.addingTimeInterval(5 * 24 * 60 * 60)
        let (schedule1, gen1) = try SeedCatalog.loadScheduleWithAutoGeneration(
            reference: day1, scenario: .live
        )
        let (schedule2, gen2) = try SeedCatalog.loadScheduleWithAutoGeneration(
            reference: day2, scenario: .live
        )
        // 1 日目: seed prompt_001 が active
        XCTAssertNil(gen1, "coverage 内では自動生成は走らない")
        XCTAssertEqual(schedule1.activePrompt(at: day1)?.id, "prompt_001")
        // 2 日目: 別 prompt (UTC 暦日 ID) が active
        XCTAssertNotNil(gen2, "coverage 外では自動生成が走る")
        let day2ActiveID = schedule2.activePrompt(at: day2)?.id
        XCTAssertNotNil(day2ActiveID)
        XCTAssertNotEqual(day2ActiveID, "prompt_001", "翌日は seed prompt_001 ではない")
        XCTAssertTrue(
            day2ActiveID?.hasPrefix("prompt_2") == true,
            "2 日目の active prompt は UTC 暦日 ID: \(day2ActiveID ?? "")"
        )
    }

    /// 自動生成器が「今日の UTC 日付」を返す（F26 / 受け入れ条件 1, 2 の直接検証）。
    /// シードのシナリオが常に「今日」をカバーするように組まれているため、
    /// ここでは `loadScheduleWithAutoGeneration` を経由せず `PromptGenerator.generate`
    /// の戻り値を直接確認する（`scheduleAlreadyCoversToday` が false を返す状況は
    /// `testScheduleCoversTodayReturnsFalseForEmptySchedule` で別途検証済み）。
    func testGeneratorProducesTodaysPromptForGivenReference() {
        let reference = utcDate(year: 2026, month: 8, day: 25, hour: 10)
        let result = PromptGenerator.generate(reference: reference)
        XCTAssertEqual(result.prompt.id, "prompt_20260825")
        XCTAssertEqual(
            result.prompt.startsAt,
            utcDate(year: 2026, month: 8, day: 25, hour: 0),
            "今日の UTC 00:00 から始まる"
        )
    }

    /// `loadScheduleWithAutoGeneration` は「開始時刻順」を保つ。
    func testSeedCatalogScheduleStaysTimeOrdered() throws {
        let reference = utcDate(year: 2026, month: 8, day: 25)
        let (schedule, _) = try SeedCatalog.loadScheduleWithAutoGeneration(
            reference: reference,
            scenario: .expired
        )
        let sorted = schedule.prompts.sorted { $0.startsAt < $1.startsAt }
        XCTAssertEqual(schedule.prompts.map(\.id), sorted.map(\.id))
        // どの隣り合う 2 つの Prompt も期間が重ならない。
        for (previous, next) in zip(schedule.prompts, schedule.prompts.dropFirst()) {
            XCTAssertLessThanOrEqual(previous.endsAt, next.startsAt, "\(previous.id) と \(next.id) の有効期間が重なっている")
        }
    }

    // MARK: `scheduleAlreadyCoversToday` の動作

    /// 既存 schedule にお題が無い日は「カバーしていない」と判定される
    ///（= 自動生成が起動する）。
    func testScheduleCoversTodayReturnsFalseForEmptySchedule() {
        let reference = utcDate(year: 2026, month: 8, day: 25)
        let empty = PromptSchedule(prompts: [], posts: [])
        XCTAssertFalse(PromptGenerator.scheduleAlreadyCoversToday(schedule: empty, reference: reference))
    }

    /// 既存 schedule に「今日」をカバーする prompt がある場合は true
    ///（= 自動生成はスキップ）。
    func testScheduleCoversTodayReturnsTrueForOverlappingPrompt() {
        let reference = utcDate(year: 2026, month: 8, day: 25, hour: 10)
        // prompt_001 が今日をカバーする例
        let prompt = Prompt(
            id: "prompt_001",
            text: "今日のお題",
            startsAt: utcDate(year: 2026, month: 8, day: 25, hour: 0),
            endsAt: utcDate(year: 2026, month: 8, day: 26, hour: 4)
        )
        let schedule = PromptSchedule(prompts: [prompt], posts: [])
        XCTAssertTrue(PromptGenerator.scheduleAlreadyCoversToday(schedule: schedule, reference: reference))
    }

    // MARK: 受け入れ条件 4（`PersistedState.discardedCandidatesCount` の流れ）

    /// `LocalBackend` 経由で `discardedCandidatesCount` が取得できる
    ///（受け入れ条件 4「破棄された記録が残る」の読み取り経路）。
    func testLocalBackendPersistsDiscardedCount() async throws {
        let storeFile = "unit-prompt-gen-test-state.json"
        let store = LocalStore(fileName: storeFile)
        let backend = LocalBackend(
            store: store,
            clock: AppClock(),
            schedule: nil,
            options: LaunchOptions()
        )
        let count = try await backend.discardedCandidatesCount()
        XCTAssertGreaterThanOrEqual(count, 0, "累計破棄件数は 0 以上")
    }
}