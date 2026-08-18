import XCTest
@testable import SameQ

/// スプリント06 attempt 3 の最重要修正（不合格の原因[1]: 実機ではキャッシュしたセッションが
/// 無効になり致命的エラーで固まる）を、`TranslationSession` / 実機に依存せず直接検証する。
///
/// evaluator が実機プローブで確認した根本原因は「`TranslationSession` をそれを供給した
/// `.translationTask` の外へ持ち出して、後から再利用していた」こと。attempt 3 では
/// キャッシュ・持ち出しを一切やめ、`perform(key:body:)` は**呼ぶたびに必ず新しいセッションを
/// 要求し**、取得できたセッションは `resolve(session:)` の中（＝そのセッションが有効な
/// スコープの中）で `body` を実行し終えてから返す設計にした。`Session` をジェネリックにして
/// あるので、ここでは `String` をダミーのセッションとして使い、待ち行列のロジックだけを
/// Translation Framework 抜きで確認する。
final class SessionRequestQueueTests: XCTestCase {

    /// 同じキー（言語ペア）へ連続で要求しても、`perform` はキャッシュを返さず**毎回**
    /// 新しいセッションを要求する。これが attempt 2 のキャッシュ設計を撤去したことの
    /// 直接の確認（evaluator の実機プローブが再現した固着の根本原因への対処）。
    @MainActor
    func testSameKeyIsRequestedAgainEveryTime() async {
        var needsSessionCalls: [String] = []
        let queue = SessionRequestQueue<String>(onNeedsSession: { key in
            needsSessionCalls.append(key)
        })

        async let first: String? = queue.perform(key: "en") { session in session }
        try? await Task.sleep(nanoseconds: 20_000_000)
        await queue.resolve(session: "en-session-1")
        let firstResult = await first
        XCTAssertEqual(firstResult, "en-session-1")

        // 直前と同じキー（"en"）をもう一度要求すると、キャッシュからではなく
        // 新しいセッション要求が発生する（`onNeedsSession` が2回目も呼ばれる）。
        async let second: String? = queue.perform(key: "en") { session in session }
        try? await Task.sleep(nanoseconds: 20_000_000)
        await queue.resolve(session: "en-session-2")
        let secondResult = await second

        XCTAssertEqual(secondResult, "en-session-2")
        XCTAssertEqual(needsSessionCalls, ["en", "en"], "同じキーでも毎回新しい要求を出す")
    }

    /// evaluator の実機プローブの手順（en → ko → en）を、値の再利用が起きないことに
    /// 焦点を当てて再現する。3手目の "en" は1手目とは別の（新しい）セッションを受け取る。
    @MainActor
    func testMatchesEvaluatorReproductionSequenceWithoutReusingSessions() async {
        var needsSessionCalls: [String] = []
        let queue = SessionRequestQueue<String>(onNeedsSession: { key in
            needsSessionCalls.append(key)
        })

        async let request1: String? = queue.perform(key: "en") { $0 }
        try? await Task.sleep(nanoseconds: 20_000_000)
        await queue.resolve(session: "session-en-1")
        let result1 = await request1
        XCTAssertEqual(result1, "session-en-1")

        async let request2: String? = queue.perform(key: "ko") { $0 }
        try? await Task.sleep(nanoseconds: 20_000_000)
        await queue.resolve(session: "session-ko")
        let result2 = await request2
        XCTAssertEqual(result2, "session-ko")

        // 3件目: 最初の言語ペア（"en"）にまた戻ってきても、1件目のセッションは
        // 二度と使われない（新しいセッションを要求し、新しい値を受け取る）。
        async let request3: String? = queue.perform(key: "en") { $0 }
        try? await Task.sleep(nanoseconds: 20_000_000)
        await queue.resolve(session: "session-en-2")
        let result3 = await request3
        XCTAssertEqual(result3, "session-en-2")
        XCTAssertNotEqual(result1, result3, "1件目のセッションを3件目で使い回してはいけない")

        XCTAssertEqual(needsSessionCalls, ["en", "ko", "en"], "毎回新しい要求を出すはず")
    }

    /// 取得したセッションは `resolve` の中で `body` に渡され、`body` の完了を待ってから
    /// `resolve` 自身が完了する（＝セッションが有効なスコープの中で使い切られる）。
    @MainActor
    func testBodyRunsToCompletionInsideResolveBeforeQueueAdvances() async {
        var events: [String] = []
        let queue = SessionRequestQueue<String>(onNeedsSession: { key in
            events.append("needs(\(key))")
        })

        async let result: String? = queue.perform(key: "en") { session in
            events.append("body-start")
            try? await Task.sleep(nanoseconds: 30_000_000)
            events.append("body-end")
            return "translated:\(session)"
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
        events.append("resolve-call")
        await queue.resolve(session: "en-session")
        events.append("resolve-return")

        let value = await result
        XCTAssertEqual(value, "translated:en-session")
        XCTAssertEqual(events, ["needs(en)", "resolve-call", "body-start", "body-end", "resolve-return"],
                        "body の完了を待ってから resolve が返るはず（セッションが外へ漏れない設計の核心）")
    }

    /// 保険: セッションの取得自体が一定時間内に来なければタイムアウトで諦め、
    /// 後続の要求（別のキー）へ進める（永久に固まらない）。
    @MainActor
    func testAcquireTimeoutRecoversAndDoesNotBlockSubsequentRequests() async {
        var needsSessionCalls: [String] = []
        // テストで実時間を待たないよう `sleep` を差し替える。"en" だけ即座にタイムアウトさせ、
        // それ以外のキーは（テスト側が手動で `resolve` するまで）十分長く待たせる。
        let queue = SessionRequestQueue<String>(
            acquireTimeoutSeconds: 0.01,
            sleep: { key, _ in
                if key == "en" { return }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            },
            onNeedsSession: { key in needsSessionCalls.append(key) }
        )

        // "en" は誰も resolve しないのでタイムアウトする（body は一度も呼ばれない）。
        var bodyCalled = false
        let timedOut: String? = await queue.perform(key: "en") { _ in
            bodyCalled = true
            return "unreachable"
        }
        XCTAssertNil(timedOut, "タイムアウトしたら nil を返す")
        XCTAssertFalse(bodyCalled, "セッションが来ていないので body は呼ばれない")

        // 固まらず、次の要求（別のキー）を処理できる。
        async let ko: String? = queue.perform(key: "ko") { $0 }
        try? await Task.sleep(nanoseconds: 20_000_000)
        await queue.resolve(session: "session-ko")
        let result = await ko
        XCTAssertEqual(result, "session-ko")
        XCTAssertEqual(needsSessionCalls, ["en", "ko"])
    }

    /// 保険: セッションは取得できたが `body`（実際には `session.translate(_:)`）が
    /// 返ってこない場合、`jobTimeoutSeconds` を超えたら `nil` を返し、`onJobTimeout` を
    /// 呼ぶ（不合格の原因[3]: `translate(_:)` 自体にも時間制限が無い、への対応）。
    ///
    /// `sleep` はキュー内の2箇所（セッション取得の待ち＝`key` に要求キーが入る／
    /// ジョブ実行のタイムアウト競走＝`key` が空文字列）で使われる。ここでは
    /// 空文字列のときだけ短く待たせ、それ以外（セッション取得側）は本テストの検証時間より
    /// 十分長く待たせることで、2つのタイムアウトが競合しないようにする。
    @MainActor
    func testJobTimeoutGivesUpAndCallsOnJobTimeout() async {
        let queue = SessionRequestQueue<String>(
            sleep: { key, _ in
                if key.isEmpty {
                    try? await Task.sleep(nanoseconds: 5_000_000)
                } else {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
            },
            onNeedsSession: { _ in }
        )

        var onJobTimeoutCalledWith: String?
        async let result: String? = queue.perform(
            key: "en",
            body: { session in
                // 現実の「返ってこない `session.translate(_:)`」を模した、長時間ハングする body。
                // `Task.sleep` は協調的キャンセルに応答するため、`onJobTimeout` 後の
                // `group.cancelAll()` でこの待ちはすぐに終わる（本テストが5秒かからないことも
                // あわせて確認している）。
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                return "should-not-reach-here"
            },
            onJobTimeout: { session in onJobTimeoutCalledWith = session }
        )
        try? await Task.sleep(nanoseconds: 20_000_000)
        await queue.resolve(session: "en-session")

        let value = await result
        XCTAssertNil(value, "body がタイムアウトしたら nil を返す")
        XCTAssertEqual(onJobTimeoutCalledWith, "en-session", "onJobTimeout にそのセッションを渡す")
    }

    /// ジョブタイムアウト後も、次の要求（別のキー）へ正しく進める（永久に固まらない）。
    @MainActor
    func testAfterJobTimeoutQueueAdvancesToNextRequest() async {
        var needsSessionCalls: [String] = []
        let queue = SessionRequestQueue<String>(
            sleep: { key, _ in
                if key.isEmpty {
                    try? await Task.sleep(nanoseconds: 5_000_000)
                } else {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
            },
            onNeedsSession: { key in needsSessionCalls.append(key) }
        )

        async let first: String? = queue.perform(key: "en") { _ in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            return "unreachable"
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        await queue.resolve(session: "en-session")
        let firstResult = await first
        XCTAssertNil(firstResult)

        // 次の要求（別のキー）は正常に処理できる。
        async let second: String? = queue.perform(key: "ko") { $0 }
        try? await Task.sleep(nanoseconds: 20_000_000)
        await queue.resolve(session: "session-ko")
        let secondResult = await second
        XCTAssertEqual(secondResult, "session-ko")
        XCTAssertEqual(needsSessionCalls, ["en", "ko"])
    }
}
