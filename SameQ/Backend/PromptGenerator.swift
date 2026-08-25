import Foundation

/// 1 日 1 回のお題自動生成（F26 / F27）。
///
/// 端末ローカルだけで「世界共通」のお題を組み立てる。`PromptCatalog.candidatePool`
/// から **UTC の暦日 (`yyyy-MM-dd`)** を起点に決定的に候補を選ぶ。同じ UTC 日付には
/// 同じ端末・同じアカウント・別のアカウント・別の端末でも同じ Prompt が返る
///（受け入れ条件 2:「同じ時刻に別のアカウント／別の端末で開いても、同一のお題」）。
///
/// 真にサーバーが一意なソースを持たない以上、ここでの「世界共通」は擬似的なもの
///（＝ Supabase 移行後の厳密な世界共通はサーバー側の責務）だが、仕様の要求を
/// ローカル端末の範囲で満たすには十分。
enum PromptGenerator {

    /// 1 件生成したときの結果（採用された Prompt と、破棄された候補の内訳）。
    ///
    /// `discarded` は受け入れ条件 4 の「破棄された記録」の表示用データ。
    /// UI には出さないが、`LocalBackend` が `PersistedState` に件数を積算する。
    struct GenerationResult: Equatable, Sendable {
        /// 採用された Prompt。破棄が起きてフォールバックした場合も、
        /// フォールバック候補の Prompt がそのまま入る。
        let prompt: Prompt
        /// 採用されなかった候補の記録（受け入れ条件 4）。`text` は原文のまま残す
        ///（重複が起きたときに運用側で内容を確認できるように）。
        let discarded: [DiscardedCandidate]
        /// 採用が「`PromptCatalog.candidatePool` の正常候補」だったか
        ///「全滅したのでフォールバックしたか」を区別する。
        let usedFallback: Bool
    }

    /// 破棄された候補の記録。
    ///
    /// 受け入れ条件 4 の「破棄された記録が残る」に対応する表示用データ。
    /// 仕様では UI 公開は求められていないので、`PersistedState` には件数だけ
    /// 積算して持ち、Debug オーバーレイで「discarded N」と出す。
    struct DiscardedCandidate: Equatable, Sendable {
        let text: String
        let reason: PromptCatalog.DiscardReason
        let dayKey: String
    }

    /// 起動時の `reference` について Prompt を 1 件返す（F26）。
    ///
    /// 「世界共通」の根拠にするため、暦日は **UTC 固定** で参照する
    ///（受け入れ条件 2: 端末のタイムゾーンに依らず同じ UTC 日付 → 同じ Prompt）。
    ///
    /// - Parameters:
    ///   - reference: 起動時の `clock.now`（`AppClock` 経由のオフセット後）。
    ///   - candidatePool: 採用候補のリスト（既定は `PromptCatalog.candidatePool`）。
    ///     テストで「全候補 unsafe」の状況を作るために差し替えられるように公開。
    ///   - fallbackPool: フォールバック候補（既定は `PromptCatalog.fallbackPool`）。
    static func generate(
        reference: Date,
        candidatePool: [String] = PromptCatalog.candidatePool,
        fallbackPool: [(id: String, text: String)] = PromptCatalog.fallbackPool
    ) -> GenerationResult {
        let utc = TimeZone(identifier: "UTC")!
        let dayKey = Self.dayKey(for: reference, timeZone: utc)
        let dayIndex = Self.dayIndex(for: reference, timeZone: utc)
        return generate(
            dayKey: dayKey,
            dayIndex: dayIndex,
            candidatePool: candidatePool,
            fallbackPool: fallbackPool
        )
    }

    /// テストから直接呼べる決定的な生成。日付キーは `yyyyMMdd` 形式。
    static func generate(
        dayKey: String,
        dayIndex: Int,
        candidatePool: [String] = PromptCatalog.candidatePool,
        fallbackPool: [(id: String, text: String)] = PromptCatalog.fallbackPool
    ) -> GenerationResult {
        var discarded: [DiscardedCandidate] = []

        if candidatePool.isEmpty {
            return fallbackResult(
                dayKey: dayKey,
                fallbackPool: fallbackPool,
                discarded: discarded,
                usedFallback: true
            )
        }

        let poolSize = candidatePool.count
        // 開始位置は「その日の pool 内インデックス」。隣接日に近いお題が続けて出ないよう、
        // poolSize の半分を足して中盤から走査する（端に固まるのを避ける）。
        let startIndex = ((dayIndex % poolSize) + poolSize / 2) % poolSize

        for offset in 0..<poolSize {
            let index = (startIndex + offset) % poolSize
            let candidate = candidatePool[index]
            if let reason = PromptCatalog.violationReason(in: candidate) {
                discarded.append(DiscardedCandidate(text: candidate, reason: reason, dayKey: dayKey))
                continue
            }
            let utc = TimeZone(identifier: "UTC")!
            let start = Self.startOfDay(forDayKey: dayKey, timeZone: utc)
            let prompt = Prompt(
                id: "prompt_\(dayKey)",
                text: candidate,
                startsAt: start,
                endsAt: start.addingTimeInterval(Prompt.defaultDuration),
                language: "ja"
            )
            return GenerationResult(prompt: prompt, discarded: discarded, usedFallback: false)
        }

        // 全候補が不適格 → フォールバック。
        return fallbackResult(
            dayKey: dayKey,
            fallbackPool: fallbackPool,
            discarded: discarded,
            usedFallback: true
        )
    }

    /// 候補プールが空、または全候補が不適格だった場合のフォールバック（F27）。
    ///
    /// `fallbackPool` には安全と分かっているシード文言しか入れていないので、
    /// ここに来た時点で違反はない（`violationReason` を走らせないことで
    /// 「破棄記録にフォールバック候補が紛れ込む」事故を防ぐ）。
    private static func fallbackResult(
        dayKey: String,
        fallbackPool: [(id: String, text: String)],
        discarded: [DiscardedCandidate],
        usedFallback: Bool
    ) -> GenerationResult {
        // fallbackPool も空なら仕様上「必ず何らかのお題が有効」のままなので、
        // 最後の砦として prompt_001 を返す。
        let (id, text): (String, String) = fallbackPool.first
            ?? ("prompt_001", "今日、思わず笑ってしまったことは何ですか？")
        let utc = TimeZone(identifier: "UTC")!
        let start = Self.startOfDay(forDayKey: dayKey, timeZone: utc)
        let prompt = Prompt(
            id: id,
            text: text,
            startsAt: start,
            endsAt: start.addingTimeInterval(Prompt.defaultDuration),
            language: "ja"
        )
        return GenerationResult(prompt: prompt, discarded: discarded, usedFallback: usedFallback)
    }

    /// UTC の暦日を `yyyyMMdd` に整形する。同じ日付からは常に同じ文字列。
    static func dayKey(for date: Date, timeZone: TimeZone = TimeZone(identifier: "UTC")!) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d%02d%02d", year, month, day)
    }

    /// `date` から「UTC epoch 1970-01-01 までの日数」を計算する。決定的なインデックス用。
    /// 同じ UTC 日付には同じ整数が返るので、`dayIndex % poolSize` が端末横断で一致する。
    static func dayIndex(for date: Date, timeZone: TimeZone = TimeZone(identifier: "UTC")!) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let epoch = calendar.startOfDay(for: Date(timeIntervalSince1970: 0))
        let day = calendar.startOfDay(for: date)
        let components = calendar.dateComponents([.day], from: epoch, to: day)
        return components.day ?? 0
    }

    /// `dayKey`（`yyyyMMdd`）から UTC 00:00 の `Date` を組み立てる。
    /// 開始時刻を UTC 00:00 に固定することで「翌日に別のお題」「2 つ同時に表示
    /// されない」（受け入れ条件 1, 6）を端末横断で担保する。
    static func startOfDay(forDayKey dayKey: String, timeZone: TimeZone = TimeZone(identifier: "UTC")!) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let yearString = String(dayKey.prefix(4))
        let monthString = String(dayKey.dropFirst(4).prefix(2))
        let dayString = String(dayKey.suffix(2))
        let year = Int(yearString) ?? 1970
        let month = Int(monthString) ?? 1
        let day = Int(dayString) ?? 1
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 0
        components.minute = 0
        components.second = 0
        components.timeZone = timeZone
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    /// `reference` の時点で `schedule.prompts` のいずれかが現在 active か
    ///（=「今日のお題」が既に決まっているか）を判定する。
    ///
    /// 「同じ UTC 日に既存シードの prompt_001 のようなお題がある」場合に
    /// 自動生成をスキップして、シード側のお題を採用する（受け入れ条件 6
    /// 「2 つ同時に表示されない」を満たすため。シードと自動生成が同じ
    /// 日に重なると同時にアクティブになり得る）。
    ///
    /// スプリント09 attempt 3 の修正: 旧実装は「`reference` の UTC 日と
    /// period が少しでも重なる prompt があれば true」だったが、これだと
    /// seed prompt が `reference` 時点で既に終わっているのに `scheduleAlreadyCoversToday`
    /// が true を返し続けて PromptGenerator が発火しない（= activePrompt が
    /// nil になりユーザーが「お題待ち」画面を見る）ことがあった。`isActive(at:)`
    /// を直接見ることで「いま進行中のお題があるか」を判定する。
    static func scheduleAlreadyCoversToday(schedule: PromptSchedule, reference: Date) -> Bool {
        for prompt in schedule.prompts {
            if prompt.isActive(at: reference) {
                return true
            }
        }
        return false
    }
}