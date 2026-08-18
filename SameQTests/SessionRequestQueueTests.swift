import XCTest
@testable import SameQ

/// スプリント06 attempt 2 の最重要修正（バグ1: 翻訳キューが同一言語ペアの2件目で
/// 永久に固まる）を、`TranslationSession` / シミュレータに依存せず直接検証する。
///
/// evaluator が実測した固着の直接原因は「値の等しい `TranslationSession.Configuration` を
/// 代入し直しても `.translationTask` が再実行されない」ことだった。`SessionRequestQueue` は
/// この制約があっても固まらないよう、**同じキーへは2回目以降新しい要求を出さない**設計に
/// してある。`Session` をジェネリックにしてあるので、ここでは `String` をダミーの
/// セッションとして使い、待ち行列のロジックだけを Translation Framework 抜きで確認する。
final class SessionRequestQueueTests: XCTestCase {

    /// evaluator の再現手順そのもの: 同じキーへの2件目の要求が来ても、
    /// `onNeedsSession` は1回しか呼ばれない（＝同じ値の `Configuration` を2回代入しない）。
    /// 修正前の実装（毎回新しい `Configuration` を作って代入する設計）だと、この場合
    /// 2件目の `request` は永久に解決されなかった。
    @MainActor
    func testSameKeyRequestedTwiceOnlyAsksForOneSession() async {
        var needsSessionCalls: [String] = []
        let queue = SessionRequestQueue<String>(onNeedsSession: { key in
            needsSessionCalls.append(key)
        })

        async let first = queue.request("en")
        // `request` 内の `withCheckedContinuation` がキューに積まれるまで、
        // ごく短い間だけ譲る（実運用でも `.translationTask` からの解決は非同期に来る）。
        try? await Task.sleep(nanoseconds: 20_000_000)
        queue.resolve(session: "en-session")
        let firstResult = await first
        XCTAssertEqual(firstResult, "en-session")

        // 直前と同じキー（"en"）を2回目要求しても、新しいセッションは要求されない
        // （evaluator が実測した固着の直接原因を構造的に無くしている）。
        let secondResult = await queue.request("en")
        XCTAssertEqual(secondResult, "en-session", "2回目はキャッシュから即座に返るはず")
        XCTAssertEqual(needsSessionCalls, ["en"], "同じキーで2回目の要求を出してはいけない")
    }

    /// evaluator の実測ログを再現する3手順（en → en → ko）。
    /// 「別の言語ペアなら発火する」という差分もあわせて確認する。
    @MainActor
    func testMatchesEvaluatorReproductionSequence() async {
        var needsSessionCalls: [String] = []
        let queue = SessionRequestQueue<String>(onNeedsSession: { key in
            needsSessionCalls.append(key)
        })

        async let request1 = queue.request("en")
        try? await Task.sleep(nanoseconds: 20_000_000)
        queue.resolve(session: "session-en")
        _ = await request1

        // 2件目（同じ言語ペア）: evaluator のログでは「20秒待っても返ってこない」だった。
        // 修正後はキャッシュから即座に返る。
        let request2 = await queue.request("en")
        XCTAssertEqual(request2, "session-en")

        // 3件目（別の言語ペア）: 新しい要求が発生する。
        async let request3 = queue.request("ko")
        try? await Task.sleep(nanoseconds: 20_000_000)
        queue.resolve(session: "session-ko")
        let result3 = await request3
        XCTAssertEqual(result3, "session-ko")

        XCTAssertEqual(needsSessionCalls, ["en", "ko"], "en→en→ko で要求は en・ko の2回だけのはず")

        // 4件目（最初の言語ペアにまた戻る）もキャッシュから即座に返り、要求は増えない。
        let request4 = await queue.request("en")
        XCTAssertEqual(request4, "session-en")
        XCTAssertEqual(needsSessionCalls, ["en", "ko"])
    }

    /// 同じキーへ、まだ解決していないうちに複数回 `request` しても、
    /// 新しい要求は1回だけ・全員が同じセッションを受け取る。
    @MainActor
    func testConcurrentRequestsForSameUnresolvedKeyShareOneSession() async {
        var needsSessionCalls: [String] = []
        let queue = SessionRequestQueue<String>(onNeedsSession: { key in
            needsSessionCalls.append(key)
        })

        async let a = queue.request("en")
        async let b = queue.request("en")
        async let c = queue.request("en")
        try? await Task.sleep(nanoseconds: 20_000_000)
        queue.resolve(session: "shared")

        let (resultA, resultB, resultC) = await (a, b, c)
        XCTAssertEqual([resultA, resultB, resultC], ["shared", "shared", "shared"])
        XCTAssertEqual(needsSessionCalls, ["en"], "未解決のうちの重複要求で新しい要求を増やしてはいけない")
    }

    /// 保険: セッションが一定時間内に来なければタイムアウトで諦め、
    /// 後続の要求（別のキー）へ進める（永久に固まらない）。
    @MainActor
    func testTimeoutRecoversAndDoesNotBlockSubsequentRequests() async {
        var needsSessionCalls: [String] = []
        // テストで実時間を待たないよう `sleep` を差し替える。"en" だけ即座にタイムアウトさせ、
        // それ以外のキーは（テスト側が手動で `resolve` するまで）十分長く待たせる
        // — 固定の短い秒数にすると、あとで要求する "ko" まで巻き込んで即タイムアウトしてしまうため。
        let queue = SessionRequestQueue<String>(
            timeoutSeconds: 0.01,
            sleep: { key, _ in
                if key == "en" { return }
                // `timeoutSeconds`（0.01秒）を使うと、あとで要求する "ko" までタイムアウトの
                // 対象になってしまうので、それ以外のキーはテストの検証時間より
                // 十分長く（実時間で）待たせる。
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            },
            onNeedsSession: { key in needsSessionCalls.append(key) }
        )

        // "en" は誰も resolve しないのでタイムアウトする。
        let timedOut = await queue.request("en")
        XCTAssertNil(timedOut, "タイムアウトしたら nil を返す")

        // 固まらず、次の要求（別のキー）を処理できる。
        async let ko = queue.request("ko")
        try? await Task.sleep(nanoseconds: 20_000_000)
        queue.resolve(session: "session-ko")
        let result = await ko
        XCTAssertEqual(result, "session-ko")
        XCTAssertEqual(needsSessionCalls, ["en", "ko"])
    }

    /// タイムアウト後に同じキーをもう一度要求すると、（まだキャッシュが無いので）
    /// 新しい要求を出し直せる（＝キー単位で永久に諦めたままにはならない）。
    @MainActor
    func testTimedOutKeyCanBeRequestedAgainLater() async {
        var needsSessionCalls: [String] = []
        // 1回目の "en" だけ即座にタイムアウトさせ、2回目の "en" はテストが `resolve` するまで待たせる。
        var enAttempts = 0
        let queue = SessionRequestQueue<String>(
            timeoutSeconds: 0.01,
            sleep: { key, _ in
                guard key == "en" else { return }
                enAttempts += 1
                if enAttempts == 1 { return }
                // 2回目の "en" はテストが `resolve` するまで、検証時間より十分長く待たせる。
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            },
            onNeedsSession: { key in needsSessionCalls.append(key) }
        )

        let firstAttempt = await queue.request("en")
        XCTAssertNil(firstAttempt)

        async let secondAttempt = queue.request("en")
        try? await Task.sleep(nanoseconds: 20_000_000)
        queue.resolve(session: "session-en-2")
        let result = await secondAttempt
        XCTAssertEqual(result, "session-en-2")
        XCTAssertEqual(needsSessionCalls, ["en", "en"], "タイムアウトしたキーは再要求できる")
    }
}
