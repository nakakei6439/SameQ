import XCTest
import Translation
@testable import SameQ

/// `LanguageAvailability.Status` の3値（`.installed` / `.supported` / `.unsupported`）を
/// 区別する `Translator` のロジックを、実際の `Translation` framework の実機挙動に依存せず
/// 検証する（attempt 4: eval-3.md [1] の修正）。
///
/// `-SameQFakeTranslate`（疑似翻訳モード）は `availabilityStatus` を一切通らない
/// （シミュレータでは実際の `LanguageAvailability` が全ペアで `.unsupported` を返すため、
/// `Translator.translate` が意図的にバイパスしている。`TranslatorFakeModeTests` を参照）。
/// ここでは `LanguageAvailabilityProviding` を差し替えて、実機でしか本来得られない
/// `.supported`（モデル未ダウンロード）を注入し、**`session.translate(_:)` へ絶対に
/// 進まないこと**（＝OSのダウンロード確認シートを出させる経路に一切入らないこと）を
/// 確定的に確認する。
final class TranslatorAvailabilityTests: XCTestCase {

    /// テスト用の呼び出し記録。`Translator` は `@MainActor` から呼ぶが、プロトコルの
    /// 要件自体はアクター非隔離のため、`actor` にして安全に記録する。
    private actor CallLog {
        private(set) var sourceCodes: [String] = []
        func record(_ code: String) { sourceCodes.append(code) }
    }

    private struct FakeAvailability: LanguageAvailabilityProviding {
        let statusesByLowercasedSourceCode: [String: LanguageAvailability.Status]
        let log: CallLog

        func status(from source: Locale.Language, to target: Locale.Language?) async -> LanguageAvailability.Status {
            let code = (source.languageCode?.identifier ?? "").lowercased()
            await log.record(code)
            return statusesByLowercasedSourceCode[code] ?? .unsupported
        }
    }

    /// [最重要] `.supported`（モデル未ダウンロード）は `session.translate(_:)` に一切進まない。
    /// `translator.configuration` が呼び出し前後で nil のまま（＝`.translationTask` へ
    /// 一度もセッションを要求していない）ことを確認する。これが実機の不合格の直接原因
    /// （OSの「翻訳／必要なダウンロード」確認シートがタイムライン画面ごと閉じてしまう）の
    /// 再発防止の核心。
    @MainActor
    func testSupportedStatusNeverRequestsASessionAndSkipsAsTemporaryFailure() async {
        let log = CallLog()
        let availability = FakeAvailability(statusesByLowercasedSourceCode: ["pl": .supported], log: log)
        let translator = Translator(availability: availability, fakeTranslate: false, preferredLanguageIdentifier: "ja")

        XCTAssertNil(translator.configuration, "呼び出し前は当然まだ何も要求していない")
        let outcome = await translator.translate("Cześć", sourceLanguageCode: "pl")
        XCTAssertEqual(outcome, .unavailable(permanent: false), ".supported は一時的な失敗として読み飛ばすはず")
        XCTAssertNil(
            translator.configuration,
            ".supported のときは session.translate(_:) へ一切進んではいけない（OSのダウンロード確認シートの原因）"
        )
    }

    /// `.unsupported` は従来どおり恒久的な失敗として扱い、以後は問い合わせ自体を
    /// キャッシュする（既存の `unsupportedSourceCodes` の仕組みを維持していることの確認）。
    @MainActor
    func testUnsupportedStatusIsPermanentAndCached() async {
        let log = CallLog()
        let availability = FakeAvailability(statusesByLowercasedSourceCode: ["zz": .unsupported], log: log)
        let translator = Translator(availability: availability, fakeTranslate: false, preferredLanguageIdentifier: "ja")

        let first = await translator.translate("hello", sourceLanguageCode: "zz")
        XCTAssertEqual(first, .unavailable(permanent: true))
        let second = await translator.translate("別の本文", sourceLanguageCode: "zz")
        XCTAssertEqual(second, .unavailable(permanent: true))
        XCTAssertNil(translator.configuration, ".unsupported でもセッションを要求してはいけない")

        let calls = await log.sourceCodes
        XCTAssertEqual(calls, ["zz"], "恒久的な非対応と判明したら2回目以降は問い合わせ自体を省略するはず")
    }

    /// `.supported` は端末側の状態があとで変わりうる（ユーザーが設定アプリ側でモデルを
    /// ダウンロードした場合）ので、`.unsupported` と違い毎回問い合わせる（キャッシュしない）。
    @MainActor
    func testSupportedStatusIsNotCachedBecauseItCanChangeLater() async {
        let log = CallLog()
        let availability = FakeAvailability(statusesByLowercasedSourceCode: ["pl": .supported], log: log)
        let translator = Translator(availability: availability, fakeTranslate: false, preferredLanguageIdentifier: "ja")

        _ = await translator.translate("Cześć", sourceLanguageCode: "pl")
        _ = await translator.translate("Dzień dobry", sourceLanguageCode: "pl")

        let calls = await log.sourceCodes
        XCTAssertEqual(calls, ["pl", "pl"], ".supported は毎回問い合わせるはず（あとで .installed に変わりうるため）")
    }

    /// `.installed` のときだけ、実際にセッションを要求する経路へ進む（`.supported` との
    /// 違いの確認）。このシミュレータ環境では実際に取得できる `TranslationSession` が
    /// 無いため、`translate` 自体の完了は待たない（待つと待ち行列のタイムアウトまで
    /// 掛かってしまう）。「セッションを要求したかどうか」だけを短時間で確認する。
    /// `session.translate(_:)` 呼び出しそのものは `SessionRequestQueueTests` が
    /// フレームワーク非依存に検証済み。
    @MainActor
    func testInstalledStatusProceedsToRequestASession() async {
        let log = CallLog()
        let availability = FakeAvailability(statusesByLowercasedSourceCode: ["en": .installed], log: log)
        let translator = Translator(availability: availability, fakeTranslate: false, preferredLanguageIdentifier: "ja")

        XCTAssertNil(translator.configuration)
        Task { _ = await translator.translate("Hello", sourceLanguageCode: "en") }

        var attempts = 0
        while translator.configuration == nil, attempts < 100 {
            try? await Task.sleep(nanoseconds: 10_000_000)
            attempts += 1
        }
        XCTAssertNotNil(translator.configuration, ".installed のときは .supported と違いセッションを要求するはず")
    }

    // MARK: attempt 5（eval-4.md [1]）: `prepareIfNeeded` は `.supported` を能動的にダウンロードしにいく

    /// `translate(_:)` は `.supported` のとき絶対にセッションを要求しない（上の
    /// `testSupportedStatusNeverRequestsASessionAndSkipsAsTemporaryFailure` で確認済み）が、
    /// `prepareIfNeeded(sourceLanguageCode:)` は逆に、`.supported` のときだけ
    /// `session.prepareTranslation()` のためにセッションを要求する（受け入れ条件4）。
    /// `AppSession.openTimeline()` はこれを世界タイムラインを開く**前**にしか呼ばないので、
    /// OSの確認シートが出ても巻き込んで閉じる `fullScreenCover` が存在しない
    /// （`Translator` クラス冒頭のコメントを参照）。
    @MainActor
    func testPrepareIfNeededRequestsASessionWhenSupported() async {
        let log = CallLog()
        let availability = FakeAvailability(statusesByLowercasedSourceCode: ["pl": .supported], log: log)
        let translator = Translator(
            availability: availability,
            fakeTranslate: false,
            preferredLanguageIdentifier: "ja",
            sessionAcquireTimeoutSeconds: 0.2,
            modelPrepareJobTimeoutSeconds: 0.2
        )

        XCTAssertNil(translator.configuration)
        await translator.prepareIfNeeded(sourceLanguageCode: "pl")
        XCTAssertNotNil(
            translator.configuration,
            ".supported のときは prepareIfNeeded がダウンロードのためにセッションを要求するはず（attempt 4 との違い）"
        )
    }

    /// `.installed`（既にダウンロード済み）なら `prepareIfNeeded` は何もしない
    /// （無駄なセッション要求をしない）。
    @MainActor
    func testPrepareIfNeededDoesNothingWhenAlreadyInstalled() async {
        let log = CallLog()
        let availability = FakeAvailability(statusesByLowercasedSourceCode: ["en": .installed], log: log)
        let translator = Translator(
            availability: availability,
            fakeTranslate: false,
            preferredLanguageIdentifier: "ja",
            sessionAcquireTimeoutSeconds: 0.2,
            modelPrepareJobTimeoutSeconds: 0.2
        )

        await translator.prepareIfNeeded(sourceLanguageCode: "en")
        XCTAssertNil(translator.configuration, ".installed なら準備する必要が無いのでセッションを要求してはいけない")
    }

    /// `.unsupported`（恒久的に非対応）なら `prepareIfNeeded` は何もしない。
    @MainActor
    func testPrepareIfNeededDoesNothingWhenUnsupported() async {
        let log = CallLog()
        let availability = FakeAvailability(statusesByLowercasedSourceCode: ["zz": .unsupported], log: log)
        let translator = Translator(
            availability: availability,
            fakeTranslate: false,
            preferredLanguageIdentifier: "ja",
            sessionAcquireTimeoutSeconds: 0.2,
            modelPrepareJobTimeoutSeconds: 0.2
        )

        await translator.prepareIfNeeded(sourceLanguageCode: "zz")
        XCTAssertNil(translator.configuration, ".unsupported なら準備しようがないのでセッションを要求してはいけない")
    }

    // MARK: attempt 6（eval-5.md [1]）: 直近で試して駄目だった言語はクールダウンの間、再試行しない

    /// `prepareIfNeeded` を呼んで（セッション取得がタイムアウトして）失敗した直後は、
    /// `needsPreparation` が false を返す（＝クールダウン中は `AppSession` が
    /// `prepareIfNeeded` を呼び直さない）。これが「タイムラインを開くたびに毎回同じだけ
    /// 待たされる」問題（eval-5.md [1]）の直接の修正。
    @MainActor
    func testPrepareIfNeededSkipsRetryWithinCooldownAfterUnresolvedAttempt() async {
        let log = CallLog()
        let availability = FakeAvailability(statusesByLowercasedSourceCode: ["pl": .supported], log: log)
        let translator = Translator(
            availability: availability,
            fakeTranslate: false,
            preferredLanguageIdentifier: "ja",
            sessionAcquireTimeoutSeconds: 0.2,
            modelPrepareJobTimeoutSeconds: 0.2,
            modelDownloadRetryCooldownSeconds: 300
        )

        let needsBefore = await translator.needsPreparation(sourceLanguageCode: "pl")
        XCTAssertTrue(needsBefore, "まだ一度も試していないので再試行の対象のはず")

        await translator.prepareIfNeeded(sourceLanguageCode: "pl")

        let needsAfter = await translator.needsPreparation(sourceLanguageCode: "pl")
        XCTAssertFalse(needsAfter, "直近で試みたばかりなので、クールダウン中は再試行の対象ではないはず")
    }
}
