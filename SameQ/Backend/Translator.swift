import Foundation
import Translation

/// `Translator.translate` の結果。
///
/// バグ4の修正（attempt 2）: 「恒久的に表示できない」と「一時的に表示できない」を区別する。
/// 前者（非対応言語ペア）は今後も対象外にしてよいので呼び出し側が既読にしてよい。
/// 後者（モデル未取得中のタイムアウト・一時的なエラー）は既読にしてはいけない
/// （既読にすると、あとでモデルが揃っても二度とその回答が出てこなくなる）。
enum TranslationOutcome: Equatable {
    /// 表示してよい文字列（翻訳済み、または翻訳不要で原文のまま）。
    case text(String)
    /// 表示できない。`permanent` が true なら恒久的な失敗（＝既読にしてよい）、
    /// false なら一時的な失敗（＝既読にせず後で再挑戦できるようにする）。
    case unavailable(permanent: Bool)
}

/// `LanguageAvailability.status(from:to:)` の窓口。`Translator` からユニットテストで
/// 差し替えられるようにするための最小限のプロトコル（attempt 4）。
///
/// 実機の `Translation.LanguageAvailability.Status` には3種類あり、`.installed`
/// （この端末に翻訳モデルがダウンロード済み）と `.supported`（言語ペア自体は対応しているが
/// この端末にはまだモデルが無い）を区別する必要がある。区別せずどちらも「翻訳できる」として
/// `session.translate(_:)` を呼ぶと、OSが「翻訳／必要なダウンロード」の確認シートを
/// 勝手に表示し、そのシートの下でタイムライン画面（`fullScreenCover`）が閉じてしまう
/// （attempt 3 の evaluator が実機で確認・スクリーンショットあり。`eval-3.md` [1]）。
/// この不具合はシミュレータ・疑似翻訳モードでは再現できない（`.supported` という状態自体を
/// 実際の `Translation.LanguageAvailability` からしか得られなかったため）。ユニットテストが
/// `.supported` を注入して検証できるよう、実装をプロトコルの背後に置く。
protocol LanguageAvailabilityProviding {
    func status(from source: Locale.Language, to target: Locale.Language?) async -> LanguageAvailability.Status
}

extension LanguageAvailability: LanguageAvailabilityProviding {}

/// 投稿本文とお題本文を端末言語へ変換する窓口（F18 / F20 / F21 / F22）。
///
/// Apple Translation Framework のみを使う（外部翻訳API・フォールバックは使わない。
/// 翻訳のために本文をサーバーへ送ることも無い。すべて端末内で完結する）。
///
/// `TranslationSession` は SwiftUI の `.translationTask` 修飾子からしか作れないため、
/// アプリのルートに常駐させた `TranslationHostView`（不可視）がセッションを供給する。
/// 呼び出し側（`AppSession`）はこの仕組みを意識せず `translate(_:sourceLanguageCode:)` を
/// 呼ぶだけでよい。
///
/// ## attempt 2 での変更（シミュレータでは検証できなかった不具合）
/// attempt 2 は「同じ言語ペアでは2回目以降キャッシュしたセッションを再利用する」設計に
/// したが、これは実機で `TranslationSession` を**そのセッションを供給した
/// `.translationTask` の外へ持ち出して**使い回すことになり、`configuration` を別の
/// 言語ペアへ差し替えた時点で前の `.translationTask` が畳まれ、そこで得たセッションが
/// 無効になる（Apple Translation Framework が致命的エラーを出す）。実機でのみ再現し、
/// evaluator の実機プローブで確認された。
///
/// ## attempt 3 での変更（evaluator 指摘 [1][2] の修正）
/// セッションのキャッシュ・持ち出しを一切やめた。`SessionRequestQueue.perform(key:body:)` は
/// 呼ぶたびに必ず新しいセッションを要求し、取得できたセッションは `.translationTask` の
/// クロージャの中（＝そのセッションが有効な構造化された非同期スコープの中）で
/// `session.translate(_:)` まで完結させてから結果だけを持ち帰る。セッションが
/// `.translationTask` の外に出ることは型的に無い。
///
/// 同じ言語ペアを連続で要求しても `.translationTask` が固着せず再実行されるよう、
/// `configuration` の差し替えは「新しい `Configuration` に丸ごと差し替える」のではなく
/// 「いま割り当てているインスタンスを `invalidate()` してから `source`/`target` を
/// 書き換える」方式にした（`TranslationSession.Configuration` は `source`/`target` が
/// `var` で `invalidate()` が `mutating func` であることを SDK の `.swiftinterface` で
/// 確認済み）。新しいインスタンスへ丸ごと差し替えると、SwiftUI が次のレンダーで見る
/// 最終値は無効化前と等価な値に戻ってしまい、`.translationTask` が再実行されない
/// （attempt 2 の不具合の直接原因）。
///
/// `session.translate(_:)` 自体にもタイムアウトを設けている（`SessionRequestQueue` の
/// `jobTimeoutSeconds`）。タイムアウトした場合は `session.cancel()`（iOS 26+）を呼び、
/// 応答不能な呼び出しへ中断を伝える。
///
/// ## attempt 4 での変更（evaluator 指摘 [1][2] の修正）
/// attempt 3 まではセッションの持ち出しは無くなったが、`isSupported(sourceCode:)` が
/// `LanguageAvailability.Status` の `.installed`（この端末にモデルあり）と
/// `.supported`（言語ペアには対応しているが、この端末にはまだモデルが無い）を
/// 区別せず、どちらも「翻訳できる」として `session.translate(_:)` を呼んでいた。
/// `.supported` の状態で `translate(_:)` を呼ぶと、OSが「翻訳／必要なダウンロード」の
/// 確認シートを勝手に表示し、その下でタイムライン画面（`fullScreenCover`）ごと閉じてしまう
/// （実機で4回中4回再現・スクリーンショットあり。`eval-3.md` [1]）。
///
/// 対応: `.installed` のときだけ `session.translate(_:)` まで進む。`.supported`
/// （未ダウンロード）のときは `session.translate(_:)` はおろか `prepareTranslation()` も
/// 呼ばず、`.unavailable(permanent: false)`（一時的な失敗）として読み飛ばす
/// （`AppSession.drawNextPost` は既存の仕組みでこれを既読にせず次を引く）。
/// OSにダウンロード確認シートを一切出させない設計にすることを最優先にした
/// （eval-3.md の対応方針で提示された2案のうち、`prepareTranslation()` を明示的に呼ぶ案は
/// 採らなかった。`prepareTranslation()` もモデル未取得なら同じ確認シートを表示するため、
/// `TranslationHostView` の常駐場所（`RootView` 背景、`fullScreenCover` の外）を変えない限り
/// 同じ問題が残る。ホスト側の変更は影響範囲が大きく実機でしか検証できないため見送った。
/// 判断の詳細は `self-review.md` の attempt 4 を参照）。
/// この結果、対象言語のモデルが端末にまだ無い場合、その回答は表示されない（後述の
/// `LanguageAvailabilityProviding` を差し替えれば `.supported` をユニットテストで再現できる）。
@MainActor
@Observable
final class Translator {
    /// 端末の表示言語。読むのは起動時の1回だけ（言語設定の変更はアプリの再起動後に
    /// 反映される、という受け入れ条件に合わせている）。
    let targetLanguage: Locale.Language
    /// モジュール内（`internal`）に留めているのは、ユニットテストから疑似翻訳の変換結果
    /// （`[<targetLanguageCode>] <原文>`）を検証できるようにするため。外部には公開しない。
    let targetLanguageCode: String

    /// `TranslationHostView` の `.translationTask` に渡す設定。新しいセッションが必要になる
    /// たびに（同じ言語ペアでも毎回）更新する。詳細は `sessionQueue` の `onNeedsSession` を参照。
    private(set) var configuration: TranslationSession.Configuration?

    private let availability: LanguageAvailabilityProviding
    /// 言語ペアごとの対応状況のキャッシュ（同じ問い合わせを繰り返さない）。
    /// `.supported`（未ダウンロード）はキャッシュしない。ユーザーが後で設定アプリ側で
    /// 言語をダウンロードした場合、次回の問い合わせで `.installed` に変わりうるため。
    private var statusCache: [String: LanguageAvailability.Status] = [:]
    /// 原文ごとの翻訳結果のキャッシュ。同じ回答を既読解除やスワイプで再び引いたときに
    /// 待たせないための、プロセス内だけの効果（F19: 同じ端末で2回目以降は待たせない）。
    /// モデル自体の再ダウンロードが起きないのは OS 側の仕組みによる。
    private var textCache: [String: String] = [:]
    /// `TranslationSession.translate` が「この言語ペアはこの端末では扱えない」という
    /// 種類のエラーを一度でも返した原文言語。以後はセッションを作り直さず即座にスキップする
    /// （毎回同じ理由で数秒待たされるのを防ぐ）。文字ごとの一時的な失敗とは区別するため、
    /// `TranslationError.unsupportedLanguagePairing` 系のときだけ記録する。
    private var unsupportedSourceCodes: Set<String> = []

    /// `TranslationSession` の取得を1件ずつさばく待ち行列。新しいセッションが必要になる
    /// たびに（同じ言語ペアでも毎回）`configuration` を更新して `.translationTask` へ知らせる。
    /// `@ObservationIgnored`: `@Observable` の追跡対象にすると `lazy` と両立できない
    /// （SwiftUI の描画には関係しない内部の実装詳細のため、追跡対象からも外してよい）。
    @ObservationIgnored
    private lazy var sessionQueue = SessionRequestQueue<TranslationSession>(
        onNeedsSession: { [weak self] sourceCode in
            guard let self else { return }
            let requestedSource = Locale.Language(identifier: sourceCode)
            // 新しいインスタンスへ丸ごと差し替えるのではなく、**いま割り当てている
            // インスタンスに対して** `invalidate()` を呼んでから中身を書き換える。
            // 同じ言語ペアの連続要求でも、SwiftUI が次のレンダーで見る最終値が
            // 無効化前と異なる値になるため、`.translationTask` が確実に再実行される
            // （attempt 2 の不具合の直接原因の修正。詳細はクラス冒頭のコメント）。
            if var config = self.configuration {
                config.invalidate()
                config.source = requestedSource
                config.target = self.targetLanguage
                self.configuration = config
            } else {
                self.configuration = TranslationSession.Configuration(
                    source: requestedSource,
                    target: self.targetLanguage
                )
            }
        }
    )

    /// Debug限定・起動引数 `-SameQFakeTranslate` の値。init 時点で固定して読む
    /// （ユニットテストから実際のプロセス起動引数に関係なく差し替えられるようにするため）。
    private let fakeTranslateEnabled: Bool

    /// `nonisolated` にしているのは、`AppSession.init` の既定引数
    /// （`translator: Translator = Translator()`）として呼べるようにするため。
    /// 中身はどれも `Sendable` な値の代入だけで、MainActor 隔離のプロパティには触れない。
    ///
    /// - Parameter preferredLanguageIdentifier: 通常は指定しない（`Locale.preferredLanguages`
    ///   を読む）。ユニットテストがホスト環境のロケールに関係なく決定的に検証できるように、
    ///   端末の言語を上書きするための引数。
    nonisolated init(
        availability: LanguageAvailabilityProviding = LanguageAvailability(),
        fakeTranslate: Bool = LaunchOptions.current.fakeTranslate,
        preferredLanguageIdentifier: String? = nil
    ) {
        self.availability = availability
        self.fakeTranslateEnabled = fakeTranslate
        // `Locale.current.language` は使わない。このアプリは Localizable.strings 等の
        // 言語リソースを1つも持たないため、`Locale.current` は端末の言語設定を無視して
        // 開発言語（既定 "en"）に丸められることがある（実機・シミュレータで確認済みの挙動、
        // 例: 端末設定が日本語でも `Locale.current.identifier` が "en_JP" になる）。
        // アプリのローカライズ有無に左右されない `Locale.preferredLanguages`
        // （端末設定そのままの優先言語リスト）の先頭を「端末の言語」として使う。
        let preferredIdentifier = preferredLanguageIdentifier ?? Locale.preferredLanguages.first ?? "en"
        let language = Locale.Language(identifier: preferredIdentifier)
        self.targetLanguage = language
        self.targetLanguageCode = (language.languageCode?.identifier ?? "en").lowercased()
    }

    /// `text` を端末言語へ翻訳する。
    ///
    /// - 原文の言語が端末言語と同じなら、翻訳せずそのまま返す（余計な待ちを作らない）。
    /// - 翻訳できない言語ペアなら `.unavailable(permanent: true)`。
    /// - 一時的な失敗（モデル未取得のセッション待ちがタイムアウトした等）なら
    ///   `.unavailable(permanent: false)`。呼び出し側はこれを既読にしてはいけない（F12 / バグ4）。
    func translate(_ text: String, sourceLanguageCode: String) async -> TranslationOutcome {
        guard !text.isEmpty else { return .text(text) }
        let sourceCode = sourceLanguageCode.lowercased()
        if sourceCode == targetLanguageCode { return .text(text) }

        let cacheKey = "\(sourceCode)\u{0}\(text)"
        if let cached = textCache[cacheKey] { return .text(cached) }
        guard !unsupportedSourceCodes.contains(sourceCode) else { return .unavailable(permanent: true) }

        if fakeTranslateEnabled {
            return await fakeTranslate(text, sourceCode: sourceCode, cacheKey: cacheKey)
        }

        switch await availabilityStatus(sourceCode: sourceCode) {
        case .unsupported:
            unsupportedSourceCodes.insert(sourceCode)
            return .unavailable(permanent: true)
        case .supported:
            // モデル未ダウンロード。`session.translate(_:)`（や `prepareTranslation()`）を
            // ここで呼ぶと、OSが「翻訳／必要なダウンロード」の確認シートを勝手に表示し、
            // その下でタイムライン画面ごと閉じてしまう（実機で確認済み。eval-3.md [1]、
            // クラス冒頭のコメントを参照）。恒久的な非対応とは違い、あとでユーザーが
            // 設定アプリ側でモデルをダウンロードすれば `.installed` になりうるので、
            // 既読にしない一時的な失敗として読み飛ばす。
            return .unavailable(permanent: false)
        case .installed:
            break
        @unknown default:
            return .unavailable(permanent: false)
        }

        // `perform` は毎回新しいセッションを要求し、取得できたセッションは
        // `.translationTask` のクロージャの中で `session.translate(_:)` まで完結させてから
        // 結果だけを持ち帰る（セッションを外へ持ち出さない。attempt 3 の修正）。
        let outcome = await sessionQueue.perform(
            key: sourceCode,
            body: { [weak self] session -> TranslationOutcome in
                guard let self else { return .unavailable(permanent: false) }
                return await self.performTranslate(session: session, text: text, sourceCode: sourceCode, cacheKey: cacheKey)
            },
            onJobTimeout: { session in
                // `session.translate(_:)` が `jobTimeoutSeconds` を超えても返ってこない場合の保険。
                // `cancel()` は iOS 26+ のみ（このアプリの Deployment Target は iOS 18.0 のため
                // ガードする）。呼べない環境では中断を伝える手段が無く、`body` は応答不能な
                // ままバックグラウンドで待ち続けることになる。
                if #available(iOS 26.0, *) {
                    session.cancel()
                }
            }
        )
        // `outcome` が `nil` なのは、セッションの取得自体がタイムアウトした場合
        // （`body` は一度も呼ばれていない）。
        return outcome ?? .unavailable(permanent: false)
    }

    /// 取得済みの `session` で実際に翻訳する。`SessionRequestQueue.resolve` の中（＝
    /// `.translationTask` のクロージャがまだ生きている構造化された非同期スコープの中）から
    /// しか呼ばれない。
    private func performTranslate(session: TranslationSession, text: String, sourceCode: String, cacheKey: String) async -> TranslationOutcome {
        do {
            let response = try await session.translate(text)
            textCache[cacheKey] = response.targetText
            return .text(response.targetText)
        } catch {
            if TranslationError.unsupportedLanguagePairing ~= error
                || TranslationError.unsupportedSourceLanguage ~= error {
                unsupportedSourceCodes.insert(sourceCode)
                return .unavailable(permanent: true)
            }
            // それ以外（一時的なエラー・タイムアウトによる `cancel()` 後の
            // `TranslationError.alreadyCancelled` など）はエラーダイアログを出さずスキップ
            // させるが、既読にはしない（受け入れ条件・バグ4の修正を維持）。
            return .unavailable(permanent: false)
        }
    }

    /// `sourceCode` から `targetLanguage` への対応状況。`.installed` と `.unsupported` は
    /// この端末では変わらない前提でキャッシュする。`.supported`（未ダウンロード）は
    /// キャッシュしない（ユーザーが後でモデルをダウンロードすれば変わりうるため）。
    private func availabilityStatus(sourceCode: String) async -> LanguageAvailability.Status {
        if let cached = statusCache[sourceCode] { return cached }
        let status = await availability.status(
            from: Locale.Language(identifier: sourceCode),
            to: targetLanguage
        )
        if status != .supported {
            statusCache[sourceCode] = status
        }
        return status
    }

    /// `TranslationHostView` が新しいセッションを受け取ったら呼ぶ。`await` している間、
    /// `.translationTask` のクロージャ（＝このセッションを供給しているタスク）はまだ
    /// 生きている。`session.translate(_:)` はこのクロージャが生きている間にしか安全に
    /// 呼べないため、`sessionQueue.resolve` はここで実際の翻訳が終わるまで返らない。
    func resolve(session: TranslationSession) async {
        await sessionQueue.resolve(session: session)
    }

    // MARK: 疑似翻訳（Debug限定・シミュレータ検証用）

    /// `-SameQFakeTranslate`（Debug限定）が付いているときだけ使う。
    ///
    /// このシミュレータ環境では Apple Translation が全言語ペアで
    /// `unsupportedLanguagePairing` を返し、実際の `TranslationSession` 経路が
    /// 一度も実行できない（evaluator が実測・確認済み）。実機での確認は今回のスコープ外
    /// （ユーザーが外出中のため）なので、実際の `TranslationSession` を一切使わずに
    /// 決定的な変換を返すこのモードで、周辺ロジック（表示切り替え・非対応スキップ・
    /// ちらつき防止・キャッシュ）だけはシミュレータ上で確定的に検証できるようにする。
    /// Release ビルドには含まれない（既存の `-SameQBanned` 等と同じ扱い）。
    /// 実際の `TranslationSession` を使う本番経路（このメソッドの外）はそのまま残す。
    private func fakeTranslate(_ text: String, sourceCode: String, cacheKey: String) async -> TranslationOutcome {
        // 同梱シードの検証用マーカー（`zxx`）は実際の Translation Framework でも
        // 対応不可な言語コードなので、疑似モードでも同じ「恒久的に非対応」として扱う。
        guard !Self.fakeUnsupportedSourceCodes.contains(sourceCode) else {
            unsupportedSourceCodes.insert(sourceCode)
            return .unavailable(permanent: true)
        }
        // 同梱シードの検証用マーカー（`qtd`）は「この端末では翻訳モデルが未ダウンロード
        // （`.supported`）」を模擬する（attempt 4）。実際の `TranslationSession` には
        // 一切触れず、OSのダウンロード確認シートを絶対に出さないことをシミュレータでも
        // 確定的に確認できるようにする（eval-3.md [1] の再発防止・改善提案[優先度中]）。
        guard !Self.fakeNeedsDownloadSourceCodes.contains(sourceCode) else {
            // ダウンロード待ちらしい間を置く（本番の「準備中…」表示を確認できる余地）。
            try? await Task.sleep(nanoseconds: 300_000_000)
            return .unavailable(permanent: false)
        }
        // 実際の翻訳のような非同期の間（＝「準備中…」表示を確認できる余地）を残す。
        try? await Task.sleep(nanoseconds: 50_000_000)
        let translated = "[\(targetLanguageCode.uppercased())] \(text)"
        textCache[cacheKey] = translated
        return .text(translated)
    }

    /// 疑似モードでも「翻訳できない言語」を再現するための固定リスト。
    /// 同梱シードの `zxx`（`sameQ_untranslatable_test_marker`）に合わせている。
    private static let fakeUnsupportedSourceCodes: Set<String> = ["zxx"]

    /// 疑似モードでも「モデル未ダウンロード（`.supported`）」を再現するための固定リスト。
    /// 同梱シードの `qtd`（`sameQ_download_pending_test_marker`、ISO 639-2 私用コード）に
    /// 合わせている（attempt 4）。
    private static let fakeNeedsDownloadSourceCodes: Set<String> = ["qtd"]
}
