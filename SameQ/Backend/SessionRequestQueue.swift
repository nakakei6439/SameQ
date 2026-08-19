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
///   `perform(key:jobTimeoutSeconds:body:onJobTimeout:)` の `jobTimeoutSeconds` を渡すと、
///   その呼び出しだけインスタンスの既定値を上書きできる（attempt 5: `session.translate(_:)`
///   よりずっと時間の掛かりうる `session.prepareTranslation()` に、別の長さのタイムアウトを
///   与えるため）。
///
/// ## attempt 5 で見つけた `jobTimeoutSeconds` の落とし穴（`withTaskGroup` は子タスクを待つ）
/// 当初（attempt 3）の実装は `withTaskGroup` で `body` とタイムアウト用の `sleep` を競走させ、
/// タイムアウトが勝ったら `onJobTimeout` を呼んで `cancelAll()` していた。しかし
/// `withTaskGroup` は**クロージャを抜ける前に、キャンセル済みでも残っている子タスクの完了を
/// 必ず待つ**（Swift の構造化並行性の仕様）。`session.translate(_:)` は `cancel()` を呼ぶと
/// 実際にすぐ例外を投げて終わることを attempt 3 で確認していたので実害は無かったが、
/// `session.prepareTranslation()`（attempt 5 で新規に呼ぶようになった、モデルの
/// ダウンロード）は**`cancel()` を呼んでも終わらず、実機で15分待っても `perform` 自体が
/// 一度も返ってこない**ことを実機で直接確認した（`onNeedsSession` 経由でセッション自体は
/// 取得できていたので、詰まっていたのは `body` の実行、＝`prepareTranslation()` 自体）。
/// `withTaskGroup` を使う限り、`jobTimeoutSeconds` は「タイムアウトしたことにする」だけで
/// **呼び出し元を実際には解放できない**、という設計上の欠陥だった。
///
/// 対応: `withTaskGroup`（構造化）をやめ、`body` を独立した `Task`（非構造化）として起動し、
/// `perform` 自体は `body` とタイムアウト用 `Task` のどちらが先に `continuation.resume` を
/// 呼ぶかだけで決着させる。タイムアウトが勝った場合、`body` を実行している `Task` は
/// バックグラウンドに取り残されたまま（いずれ終わる・あるいは永久に終わらない）になるが、
/// `perform` の呼び出し元は待たされずに `nil` を受け取れる。これで `jobTimeoutSeconds` が
/// 名実ともに呼び出し元の待ち時間の上限になる。
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
    /// - `body` の実行が `jobTimeoutSeconds`（省略時はインスタンスの既定値）を超えたら
    ///   `onJobTimeout(session)` を呼んで `nil` を返す（`body` 自体は `withTaskGroup` の
    ///   仕様によりバックグラウンドで完了を待ち続ける。`onJobTimeout` 側で実際に中断させる
    ///   手段があるならそこで行う）。
    /// - このキューは常に1件ずつしか処理しない。同じキーであっても要求はコアレスしない
    ///   （毎回、翻訳したいテキストが異なりうるため）。
    func perform<Result>(
        key: String,
        jobTimeoutSeconds: Double? = nil,
        body: @escaping (Session) async -> Result,
        onJobTimeout: ((Session) -> Void)? = nil
    ) async -> Result? {
        let effectiveJobTimeoutSeconds = jobTimeoutSeconds ?? self.jobTimeoutSeconds
        return await withCheckedContinuation { (continuation: CheckedContinuation<Result?, Never>) in
            let job = Job(key: key, resolve: { [weak self] session in
                guard let self, let session else {
                    continuation.resume(returning: nil)
                    return
                }
                let result = await self.runWithJobTimeout(
                    session: session,
                    timeoutSeconds: effectiveJobTimeoutSeconds,
                    body: body,
                    onJobTimeout: onJobTimeout
                )
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

    /// `body` を非構造化 `Task` として起動し、タイムアウト用 `Task` と「どちらが先に
    /// `continuation` を解決するか」だけで競走させる（attempt 5 の修正。クラス冒頭の
    /// コメントを参照）。`@MainActor` のクラスなので、2つの `Task` が同時に `hasSettled`
    /// を読み書きすることは無い（MainActor が直列化する）。
    private func runWithJobTimeout<Result>(
        session: Session,
        timeoutSeconds: Double,
        body: @escaping (Session) async -> Result,
        onJobTimeout: ((Session) -> Void)?
    ) async -> Result? {
        guard timeoutSeconds > 0 else { return await body(session) }
        let seconds = timeoutSeconds
        let sleep = self.sleep
        return await withCheckedContinuation { (continuation: CheckedContinuation<Result?, Never>) in
            var hasSettled = false
            // `body`（実際には `session.translate(_:)` や `session.prepareTranslation()`）は
            // ここでは待たない。終わり次第、まだ未解決なら結果を返す。
            Task { @MainActor in
                let result = await body(session)
                guard !hasSettled else { return }
                hasSettled = true
                continuation.resume(returning: result)
            }
            // タイムアウトが先に来たら、`body` の完了を待たずに `nil` で解決する。
            // `body` を実行している `Task` はバックグラウンドに取り残されるが（`cancel()` が
            // 効かない呼び出しは終わらないこともある）、呼び出し元はもう待たされない。
            Task { @MainActor in
                await sleep("", seconds)
                guard !hasSettled else { return }
                hasSettled = true
                onJobTimeout?(session)
                continuation.resume(returning: nil)
            }
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
