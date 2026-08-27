import XCTest

/// スプリント06（.product/spec.md 194〜201行）の修正（attempt 2）を実機操作で確かめる。
/// evaluator の手作業を置き換えるものではなく、実装側の自己確認用。
///
/// このシミュレータでは Apple Translation Framework 自体が使えない（evaluator が
/// `unsupportedLanguagePairing` を実測・確認済み）ため、Debug限定の疑似翻訳モード
/// （`-SameQFakeTranslate`）を使う。これは実際の `TranslationSession` を使わず
/// `[<言語コード>] <原文>` という決定的な変換を返すので、シミュレータでも
/// 「翻訳結果が画面へ反映される」「非対応言語は一度も現れない」「同じ言語ペアが連続しても
/// 途中で止まらない」ことを確定的に確認できる。
final class SprintSixAcceptanceTests: XCTestCase {

    private let emoji = "🌙"
    private let answerBody = "A cat looked at me like it knew something."

    /// 検証用に仕込まれた、翻訳できない言語コード（`zxx`）の回答に含まれる目印。
    private let untranslatableMarker = "sameQ_untranslatable_test_marker"

    /// 検証用に仕込まれた、モデル未ダウンロード（`.supported`）を模擬する言語コード
    /// （`qtd`）の回答に含まれる目印（attempt 4）。
    private let downloadPendingMarker = "sameQ_download_pending_test_marker"

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: 受け入れ条件1・4・6（翻訳結果の反映・待ちの発生・エラーダイアログなし）
    //       ＋ バグ1の再発防止（同じ原文言語が連続しても途中で止まらない）

    /// 疑似翻訳モードで同梱シード（多言語）をそのまま読み切るまでスワイプする。
    /// 途中で止まらず（＝待ち行列が固着せず）、翻訳された本文（`[<言語コード>] `接頭辞）が
    /// 少なくとも1件は表示され、非対応言語（`zxx`）は一度も現れないことを確認する。
    ///
    /// attempt 5（eval-4.md [1]）: モデル未ダウンロード（`.supported`）を模擬する `qtd` は、
    /// attempt 4 まで「一度も現れない」対象だったが、`AppSession.openTimeline()` が
    /// 能動的にダウンロードしてから開くようになったため、**この回答は最終的に読めるようになる
    /// はず**（＝受け入れ条件4）。`zxx`（恒久的に非対応）とは違い、いつかは表示される。
    func test01_fakeTranslateAppliesAcrossTimelineWithoutStalling() {
        let app = launch(arguments: ["-SameQFakeTranslate"], reset: true)
        completeOnboarding(app)
        submitAnswer(app, body: answerBody)
        XCTAssertTrue(app.staticTexts["timeline.card.body"].waitForExistence(timeout: 8), "1件目が出ない")

        var seenCount = 0
        var sawTranslatedPrefix = false
        var sawDownloadPendingMarkerAfterPreparation = false
        for _ in 0..<40 {
            if app.staticTexts["timeline.exhausted"].exists || app.staticTexts["timeline.empty"].exists { break }
            let card = app.staticTexts["timeline.card.body"]
            // バグ1（同じ言語ペアの2件目で永久固着）が再発していれば、ここで確実にタイムアウトする。
            guard card.waitForExistence(timeout: 10)
                || app.staticTexts["timeline.exhausted"].waitForExistence(timeout: 1) else {
                XCTFail("\(seenCount + 1)件目も読み切りも出ない（翻訳キューが固着した可能性）")
                break
            }
            guard card.exists else { break }
            XCTAssertFalse(card.label.contains(untranslatableMarker), "非対応言語の回答が表示された: \(card.label)")
            if card.label.contains(downloadPendingMarker) {
                // ダウンロード（疑似）が済んだあとなので、原文の目印を含みつつ翻訳済み接頭辞
                // 付きで表示されるはず（スキップされたまま消えてはいけない）。
                XCTAssertTrue(card.label.hasPrefix("["), "ダウンロード後は翻訳済みの表示になるはず: \(card.label)")
                sawDownloadPendingMarkerAfterPreparation = true
            }
            if card.label.hasPrefix("[") && card.label.contains("] ") {
                sawTranslatedPrefix = true
            }
            seenCount += 1
            app.swipeLeft()
        }
        XCTAssertTrue(
            app.staticTexts["timeline.exhausted"].waitForExistence(timeout: 20),
            "読み切りに到達しない（固着した可能性）"
        )
        XCTAssertGreaterThan(seenCount, 0, "1件も表示されなかった")
        XCTAssertTrue(sawTranslatedPrefix, "疑似翻訳の接頭辞（[<言語コード>] ）を持つ回答が1件も無かった")
        XCTAssertTrue(
            sawDownloadPendingMarkerAfterPreparation,
            "モデル未ダウンロードの回答が最後まで一度も表示されなかった（受け入れ条件4が満たされていない可能性）"
        )
    }

    // MARK: 受け入れ条件5（お題も端末言語で表示される）＋ バグ3の確認

    /// 同梱シードのお題は日本語原文（`promptLanguage: "ja"`）。疑似翻訳モードでは
    /// 「準備中…」を経て、`promptDisplayText` が確定した表示になる
    /// （このシミュレータの言語設定次第で、原文のままか `[<言語コード>] ` 付きかは変わるが、
    /// いずれにせよ「準備中…」のまま固まらないことを確認する）。
    func test02_promptTranslationResolvesWithoutStalling() {
        let app = launch(arguments: ["-SameQFakeTranslate"], reset: true)
        completeOnboarding(app)

        XCTAssertTrue(app.staticTexts["today.promptText"].waitForExistence(timeout: 10), "お題の表示が確定しない（準備中のまま固まった可能性）")
        XCTAssertFalse(app.otherElements["today.promptLoading"].exists, "確定後も準備中の表示が残っている")
        XCTAssertFalse(app.staticTexts["today.promptText"].label.isEmpty)
    }

    // MARK: 受け入れ条件1・3・4・6（実機の本物の Apple Translation Framework）
    //       ＋ attempt 4（eval-3.md [1][2]）の再発防止

    /// `-SameQFakeTranslate` を付けず、同梱シード（`ar`/`pl`/`ru`/`th` を含む）をそのまま
    /// 読み切るまでスワイプする。実機ではこの4言語が翻訳モデル未ダウンロード
    /// （`.supported`）だったため、OSの「翻訳／必要なダウンロード」確認シートが表示され
    /// タイムライン画面ごと閉じて二度と復帰しなかった（eval-3.md [1]、90秒待っても復帰なし）。
    /// この端末が既にモデルをダウンロード済みなら普通に翻訳されて表示されるはずで、
    /// いずれにせよ「途中で固まらない・OSシートに割り込まれない」ことを確認する。
    /// このシミュレータでは Apple Translation が全言語ペアで `unsupportedLanguagePairing` を
    /// 返す（evaluator 実測済み）ため、シミュレータ上では全件が恒久的スキップとして
    /// 即座に読み切りになる。どちらの環境でも「固まらない」ことを確認できる点は変わらない。
    ///
    /// attempt 5（eval-4.md [1]）: `AppSession.openTimeline()` は、世界タイムラインを開く前に
    /// モデル未ダウンロードの言語を能動的にダウンロードするようになった（最大90秒の予算）。
    /// そのぶん1件目が出るまでの待ちが長くなりうるので、1件目だけは長めに待つ。
    func test03_realTranslationReadsWholeSeedWithoutStallingOrOSInterruption() {
        let app = launch(arguments: [], reset: true)
        completeOnboarding(app)
        submitAnswer(app, body: answerBody)

        var seenCount = 0
        for index in 0..<40 {
            if app.staticTexts["timeline.exhausted"].exists || app.staticTexts["timeline.empty"].exists { break }
            let card = app.staticTexts["timeline.card.body"]
            // 未ダウンロードのモデルでOSシートに割り込まれて固着していれば、ここで
            // 確実にタイムアウトする。1件目だけは `openTimeline()` の能動的なダウンロード
            // （最大90秒の予算・attempt 5）を待つ必要があるので長めに、2件目以降は
            // 実機の実測最大2.5秒/件に対し十分な余裕（15秒）で待つ。
            let waitSeconds: TimeInterval = index == 0 ? 100 : 15
            guard card.waitForExistence(timeout: waitSeconds)
                || app.staticTexts["timeline.exhausted"].waitForExistence(timeout: 1) else {
                XCTFail("\(seenCount + 1)件目も読み切りも出ない（OSのダウンロード確認シートに割り込まれ固着した可能性）")
                break
            }
            guard card.exists else { break }
            XCTAssertFalse(card.label.contains(untranslatableMarker), "非対応言語の回答が表示された: \(card.label)")
            XCTAssertFalse(card.label.contains(downloadPendingMarker), "モデル未ダウンロードの回答が表示された: \(card.label)")
            seenCount += 1
            app.swipeLeft()
        }
        XCTAssertTrue(
            app.staticTexts["timeline.exhausted"].waitForExistence(timeout: 20),
            "読み切りに到達しない（OSのダウンロード確認シートに割り込まれ固着した可能性）"
        )
        // タイムラインを開いたまま最後まで閉じる操作（`timeline.close`）が生きていることも
        // 確認する（eval-3.md [2]: OSシートに割り込まれるとタイムラインが無言で閉じていた）。
        XCTAssertTrue(app.buttons["timeline.close"].isHittable, "タイムラインが閉じてしまい、閉じる操作が効かない")
    }

    // MARK: 受け入れ条件4（モデル未取得時は初回のみ準備中表示→完了後に読める）

    /// attempt 5・受け入れ条件4の核心: 読み切ったあとの Debug オーバーレイ（`-SameQDebugOverlay`）
    /// で `answers N`（候補の総数）と `viewed N`（既読の総数）を比較する。
    ///
    /// `AppSession.drawNextPost` の設計上、既読になるのは「実際に表示できた（翻訳成功、または
    /// 恒久的に非対応と判明した）」時点だけで、モデル未ダウンロードの一時的な失敗は既読に
    /// **しない**（次回また挑戦できるように）。つまり、もしモデル未ダウンロードの言語が
    /// 1件でもダウンロードに失敗したまま残っていれば `viewed < answers` のまま読み切りになる
    /// （attempt 4 の不合格そのもの）。attempt 5 で `openTimeline()` が能動的にダウンロード
    /// するようになった結果、この実機で `.supported` だった言語（`pl` / `th` / `id` など）も
    /// ダウンロードが間に合えば表示・既読になり、`viewed == answers` で読み切るはず。
    func test04_allCandidatesEventuallyBecomeViewedAfterActiveModelDownload() {
        let app = launch(arguments: ["-SameQDebugOverlay"], reset: true)
        completeOnboarding(app)
        submitAnswer(app, body: answerBody)

        // 1件目は `openTimeline()` の能動的なダウンロード（最大90秒の予算・attempt 5）を
        // 待つ必要があるので長めに待つ。
        XCTAssertTrue(
            app.staticTexts["timeline.card.body"].waitForExistence(timeout: 100)
                || app.staticTexts["timeline.exhausted"].waitForExistence(timeout: 1)
                || app.staticTexts["timeline.empty"].waitForExistence(timeout: 1),
            "1件目も読み切りも出ない（ダウンロード予算を使い切っても復帰しない可能性）"
        )
        for _ in 0..<40 {
            if app.staticTexts["timeline.exhausted"].exists || app.staticTexts["timeline.empty"].exists { break }
            guard app.staticTexts["timeline.card.body"].waitForExistence(timeout: 15) else { break }
            app.swipeLeft()
        }
        XCTAssertTrue(app.staticTexts["timeline.exhausted"].waitForExistence(timeout: 20), "読み切りに到達しない")

        // タイムライン（`fullScreenCover`）と裏の今日のお題画面の両方に Debug オーバーレイが
        // 乗っており、同時にアクセシビリティツリーへ現れることがあるので `firstMatch` を使う。
        let status = app.staticTexts.matching(identifier: "debug.status").firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 5), "Debug オーバーレイが出ていない")
        let line = status.label
        guard let answers = Self.firstInt(after: "answers ", in: line),
              let viewed = Self.firstInt(after: "viewed ", in: line) else {
            return XCTFail("Debug オーバーレイから件数を読み取れない: \(line)")
        }
        XCTAssertEqual(
            viewed, answers,
            "読み切ったのに既読件数(\(viewed))が候補総数(\(answers))に届いていない" +
            "（モデル未ダウンロードのままダウンロードに失敗した言語が残っている可能性。attempt 4 の不合格そのもの）: \(line)"
        )
    }

    private static func firstInt(after prefix: String, in text: String) -> Int? {
        guard let range = text.range(of: prefix) else { return nil }
        let rest = text[range.upperBound...]
        let digits = rest.prefix { $0.isNumber }
        return Int(digits)
    }

    // MARK: ヘルパー

    private func launch(arguments: [String], reset: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        var launchArguments = arguments
        launchArguments.append("-SameQUseLocalBackend")
        if reset { launchArguments.append("-SameQResetState") }
        app.launchArguments = launchArguments
        app.launch()
        // 2回目以降の起動でリセットが効かないよう、引数からリセットだけ外しておく
        app.launchArguments = arguments + ["-SameQUseLocalBackend"]
        return app
    }

    private func completeOnboarding(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 10))
        app.buttons["onboarding.next"].tap()                    // コンセプト
        app.buttons["onboarding.terms.agree"].tap()
        app.buttons["onboarding.next"].tap()                    // 規約
        app.buttons["onboarding.emoji.\(emoji)"].tap()
        app.buttons["onboarding.next"].tap()                    // 絵文字
        app.buttons["onboarding.next"].tap()                    // ニックネーム（未入力のまま進む）
        _ = app.keyboards.element.waitForNonExistence(timeout: 5)
        app.buttons["onboarding.notification.later"].tap()
    }

    private func submitAnswer(_ app: XCUIApplication, body: String) {
        let editor = app.textViews["today.input"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText(body)
        if app.buttons["today.doneEditing"].exists {
            app.buttons["today.doneEditing"].tap()
        }
        _ = app.keyboards.element.waitForNonExistence(timeout: 5)
        app.buttons["today.submit"].tap()
    }
}
