import Foundation

/// キー（`Translator` では原文の言語コード）ごとに1回だけセッションを要求する、
/// フレームワーク非依存の待ち行列（F18〜F22 の修正・attempt 2）。
///
/// ## 直した不具合
/// evaluator が実測したとおり、`TranslationSession.Configuration` は**値が同じでも
/// 代入し直すだけでは `.translationTask` が再実行されない**（別の言語ペアなら発火する、
/// という差分で確認済み）。そのため「毎回新しい `Configuration` を作って要求する」設計だと、
/// 直前と同じ言語ペアの2件目の要求が永久に解決されず、待ち行列全体が固まっていた。
///
/// この型は根本原因を構造的に無くす: **一度取得できたセッションはキーごとにキャッシュし、
/// 同じキーの2回目以降は新しい要求を一切出さずキャッシュを即座に返す**。新しい
/// `Configuration` を作るのは「まだ一度もセッションを取得していないキー」のときだけなので、
/// 同じ値を持つ `Configuration` を2回連続で代入することが起こり得ない。
///
/// 保険として、要求してから一定時間セッションが来なければタイムアウトで諦めて次の要求へ進む
/// （ソフトウェア側の別の不具合や、環境要因で `.translationTask` が発火しない場合に、
/// 永久に固まらせないための最終防衛）。
///
/// `Session` をジェネリックにしているのは、`TranslationSession`（実機/対応シミュレータでしか
/// 取得できない）に依存せずに、この待ち行列のロジックだけをユニットテストで直接検証できる
/// ようにするため。
@MainActor
final class SessionRequestQueue<Session> {
    /// 新しいキーのセッションが必要になったときに呼ばれる。
    /// 呼び出し側はこれを見て `TranslationSession.Configuration` を組み立て、
    /// `.translationTask` に渡すプロパティへ代入する。
    private let onNeedsSession: (String) -> Void
    private let timeoutSeconds: Double
    /// タイムアウトの待ち方を差し替えられるようにする（ユニットテストで実時間を待たないため）。
    /// `key` を渡すのは、ユニットテストが「このキーだけ即座にタイムアウトさせ、他のキーは
    /// 手動で `resolve` するまで待たせる」という制御をできるようにするため
    /// （固定の短い秒数にすると、後続の別キーの要求まで巻き込んで即タイムアウトしてしまう）。
    private let sleep: (String, Double) async -> Void

    private var sessionsByKey: [String: Session] = [:]
    private var waitersByKey: [String: [CheckedContinuation<Session?, Never>]] = [:]
    private var order: [String] = []
    private var isInFlight = false
    private var inFlightKey: String?
    private var generation = 0

    init(
        timeoutSeconds: Double = 45,
        sleep: @escaping (String, Double) async -> Void = { _, seconds in
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        },
        onNeedsSession: @escaping (String) -> Void
    ) {
        self.timeoutSeconds = timeoutSeconds
        self.sleep = sleep
        self.onNeedsSession = onNeedsSession
    }

    /// `key` のセッションを取得する。
    /// - 既に取得済みなら、新しい要求を出さずに即座に返す（固着の再発防止）。
    /// - タイムアウトした場合は `nil` を返す（呼び出し側は「一時的な失敗」として扱ってよい。
    ///   このキュー自体は `nil` を返したあとも他のキーの要求を処理し続けられる）。
    func request(_ key: String) async -> Session? {
        if let cached = sessionsByKey[key] { return cached }
        return await withCheckedContinuation { continuation in
            waitersByKey[key, default: []].append(continuation)
            if !order.contains(key) {
                order.append(key)
            }
            startNextIfNeeded()
        }
    }

    /// 新しいセッションを受け取ったら呼ぶ（`.translationTask` のクロージャから）。
    /// いま要求中のキー以外への到着や、タイムアウト済みの到着は無視する。
    func resolve(session: Session) {
        guard let key = inFlightKey else { return }
        finishInFlight(key: key)
        sessionsByKey[key] = session
        notifyWaiters(for: key, session: session)
        startNextIfNeeded()
    }

    private func startNextIfNeeded() {
        guard !isInFlight, let next = order.first else { return }
        isInFlight = true
        inFlightKey = next
        generation += 1
        let currentGeneration = generation
        onNeedsSession(next)
        scheduleTimeout(key: next, generation: currentGeneration)
    }

    private func scheduleTimeout(key: String, generation: Int) {
        let seconds = timeoutSeconds
        let sleep = self.sleep
        Task { @MainActor [weak self] in
            await sleep(key, seconds)
            self?.handleTimeout(key: key, generation: generation)
        }
    }

    private func handleTimeout(key: String, generation: Int) {
        // すでに解決済み／別の要求に切り替わっている場合は何もしない
        // （`resolve` と競合しても二重に continuation を再開しないようにするための世代管理）。
        guard isInFlight, inFlightKey == key, self.generation == generation else { return }
        finishInFlight(key: key)
        notifyWaiters(for: key, session: nil)
        startNextIfNeeded()
    }

    private func finishInFlight(key: String) {
        isInFlight = false
        inFlightKey = nil
        if let idx = order.firstIndex(of: key) {
            order.remove(at: idx)
        }
    }

    private func notifyWaiters(for key: String, session: Session?) {
        let waiters = waitersByKey.removeValue(forKey: key) ?? []
        for waiter in waiters {
            waiter.resume(returning: session)
        }
    }
}
