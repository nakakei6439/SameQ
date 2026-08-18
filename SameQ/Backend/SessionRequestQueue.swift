import Foundation

/// セッション（`Translator` では `TranslationSession`）を1件ずつ順番に取得し、
/// **そのセッションが有効なあいだに使い切ってから**結果を呼び出し側へ返す、
/// フレームワーク非依存の待ち行列（F18〜F22 の修正・attempt 3）。
///
/// ## attempt 2 の設計とその問題（evaluator が実機で発見）
/// attempt 2 は「一度取得できたセッションはキーごとにキャッシュし、同じキーの2回目以降は
/// キャッシュを再利用する」設計だった。しかし `TranslationSession` は SwiftUI の
/// `.translationTask` 修飾子のライフサイクルに紐づいており、`configuration` を別の言語ペアへ
/// 差し替えると、前の `.translationTask` は畳まれ、そこで取得したセッションは**無効になる**。
/// 無効なセッションで `translate(_:)` を呼ぶと、フレームワークが致命的エラー
/// （`Attempted to use TranslationSession after the view it was attached to has disappeared`）
/// を出す（実機のみで再現。実機プローブで直接確認済み）。キャッシュを持つ限り、この問題は
/// 構造的に避けられない。
///
/// ## attempt 3 の設計
/// セッションのキャッシュ・持ち出しを一切やめる。`perform(key:body:)` は、
/// - 呼ぶたびに**必ず**新しいセッションを要求する（`onNeedsSession` を毎回呼ぶ）。
/// - 取得できたセッションは `resolve(session:)` の呼び出し（＝`.translationTask` の
///   クロージャの中）から一度も出ることなく `body` に渡され、`body` の実行が終わるまで
///   `resolve` 自体が完了しない。つまり `body`（実際の `session.translate(_:)` 呼び出し）は
///   常に、そのセッションを供給した `.translationTask` が「まだ生きている」構造化された
///   非同期スコープの中で完結する。呼び出し側（`Translator`）がセッションを変数へ保持して
///   あとで再利用する、という経路が型的に無い。
///
/// 同じキー（言語ペア）を連続で要求しても固着しないよう、`Translator` 側で
/// `TranslationSession.Configuration.invalidate()` を正しく使う（詳細は `Translator` 側の
/// コメント）。このキュー自体はキー同士を区別しない完全な直列処理（常に1件ずつ）。
///
/// 保険として2種類のタイムアウトを持つ:
/// - `acquireTimeoutSeconds`: セッションの取得自体（`onNeedsSession` を呼んでから
///   `resolve(session:)` が来るまで）が固まった場合。
/// - `jobTimeoutSeconds`: セッションは取得できたが `body`（`session.translate(_:)`）が
///   返ってこない場合。`onJobTimeout` を呼んでから諦める（`Translator` はここで
///   `session.cancel()` を呼び、応答不能な呼び出しへ中断を伝える）。
///
/// `Session` をジェネリックにしているのは、`TranslationSession`（実機/対応シミュレータでしか
/// 取得できない）に依存せずに、この待ち行列のロジックだけをユニットテストで直接検証できる
/// ようにするため。
@MainActor
final class SessionRequestQueue<Session> {
    /// 新しいセッションが必要になったときに毎回呼ばれる（キーが同じでも毎回呼ぶ）。
    /// 呼び出し側はこれを見て `.translationTask` に渡すプロパティを更新する。
    private let onNeedsSession: (String) -> Void
    private let acquireTimeoutSeconds: Double
    private let jobTimeoutSeconds: Double
    /// タイムアウトの待ち方を差し替えられるようにする（ユニットテストで実時間を待たないため）。
    /// `key` を渡すのは、ユニットテストが「このキーだけ即座にタイムアウトさせ、他のキーは
    /// 手動で `resolve` するまで待たせる」という制御をできるようにするため。
    private let sleep: (String, Double) async -> Void

    /// タイムアウトしても `body` の完了自体は待つ設計（`withTaskGroup` の仕様上、スコープを
    /// 抜ける前に残っている子タスクの完了を待つため）なので、`.finished` と `.timedOut` を
    /// 区別できる型にしておく。
    private enum RaceOutcome<R> {
        case finished(R)
        case timedOut
    }

    /// 1件の要求。`resolve` はセッションが来たとき（`session` が非nil）はそのセッションで
    /// ジョブを実行して結果を返し、タイムアウトしたとき（`session` が nil）は何もせず
    /// `nil` で解決する。
    private struct Job {
        let key: String
        let resolve: (Session?) async -> Void
    }

    private var pendingJobs: [Job] = []
    private var currentJob: Job?
    private var isInFlight = false
    private var generation = 0

    init(
        acquireTimeoutSeconds: Double = 45,
        jobTimeoutSeconds: Double = 30,
        sleep: @escaping (String, Double) async -> Void = { _, seconds in
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        },
        onNeedsSession: @escaping (String) -> Void
    ) {
        self.acquireTimeoutSeconds = acquireTimeoutSeconds
        self.jobTimeoutSeconds = jobTimeoutSeconds
        self.sleep = sleep
        self.onNeedsSession = onNeedsSession
    }

    /// `key` のセッションを新規に要求し、取得できたら `body` を**そのセッションが有効な
    /// あいだに**実行して結果を返す。
    /// - セッションの取得自体が `acquireTimeoutSeconds` を超えたら `body` を呼ばずに `nil`。
    /// - `body` の実行が `jobTimeoutSeconds` を超えたら `onJobTimeout(session)` を呼んで
    ///   `nil` を返す（`body` 自体は `withTaskGroup` の仕様によりバックグラウンドで完了を
    ///   待ち続ける。`onJobTimeout` 側で実際に中断させる手段があるならそこで行う）。
    /// - このキューは常に1件ずつしか処理しない。同じキーであっても要求はコアレスしない
    ///   （毎回、翻訳したいテキストが異なりうるため）。
    func perform<Result>(
        key: String,
        body: @escaping (Session) async -> Result,
        onJobTimeout: ((Session) -> Void)? = nil
    ) async -> Result? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Result?, Never>) in
            let job = Job(key: key, resolve: { [weak self] session in
                guard let self, let session else {
                    continuation.resume(returning: nil)
                    return
                }
                let result = await self.runWithJobTimeout(session: session, body: body, onJobTimeout: onJobTimeout)
                continuation.resume(returning: result)
            })
            pendingJobs.append(job)
            startNextIfNeeded()
        }
    }

    /// `.translationTask` のクロージャから呼ぶ。取得したセッションをその場で `body` に渡し、
    /// `body` の実行が終わるまでこの呼び出し自体が完了しない
    /// （＝セッションは常に、それを供給したタスクの生きているスコープの中でだけ使われる）。
    func resolve(session: Session) async {
        guard let job = currentJob else { return }
        // これ以降にタイムアウトのハンドラが発火しても無視されるように、先に世代を進めて
        // in-flight 状態を確定する。
        generation += 1
        currentJob = nil
        isInFlight = false
        await job.resolve(session)
        startNextIfNeeded()
    }

    private func runWithJobTimeout<Result>(
        session: Session,
        body: @escaping (Session) async -> Result,
        onJobTimeout: ((Session) -> Void)?
    ) async -> Result? {
        guard jobTimeoutSeconds > 0 else { return await body(session) }
        let seconds = jobTimeoutSeconds
        let sleep = self.sleep
        let outcome = await withTaskGroup(of: RaceOutcome<Result>.self) { group -> RaceOutcome<Result> in
            group.addTask {
                .finished(await body(session))
            }
            group.addTask {
                await sleep("", seconds)
                return .timedOut
            }
            let first = await group.next() ?? .timedOut
            if case .timedOut = first {
                // まだ走っている `body`（実際には `session.translate(_:)`）へできるだけ早く
                // 中断を伝える。`withTaskGroup` はこのクロージャを抜ける前に残っている
                // 子タスクの完了を待つ仕様なので、ここで何もしないとタイムアウトの意味が
                // 薄れる（使い捨てスクリプトで実際に確認済み）。
                onJobTimeout?(session)
            }
            group.cancelAll()
            return first
        }
        switch outcome {
        case .finished(let result):
            return result
        case .timedOut:
            return nil
        }
    }

    private func startNextIfNeeded() {
        guard !isInFlight, !pendingJobs.isEmpty else { return }
        let job = pendingJobs.removeFirst()
        isInFlight = true
        currentJob = job
        generation += 1
        let currentGeneration = generation
        onNeedsSession(job.key)
        scheduleAcquireTimeout(key: job.key, generation: currentGeneration)
    }

    private func scheduleAcquireTimeout(key: String, generation: Int) {
        let seconds = acquireTimeoutSeconds
        let sleep = self.sleep
        Task { @MainActor [weak self] in
            await sleep(key, seconds)
            self?.handleAcquireTimeout(generation: generation)
        }
    }

    private func handleAcquireTimeout(generation: Int) {
        // すでに解決済み／別の要求に切り替わっている場合は何もしない
        // （`resolve` と競合しても二重に continuation を再開しないようにするための世代管理）。
        guard isInFlight, self.generation == generation, let job = currentJob else { return }
        currentJob = nil
        isInFlight = false
        Task { @MainActor in
            await job.resolve(nil)
            self.startNextIfNeeded()
        }
    }
}
