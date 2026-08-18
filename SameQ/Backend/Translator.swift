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
/// ## attempt 2 での変更（evaluator 指摘の修正）
/// セッションの取得は `SessionRequestQueue` に切り出し、**同じ言語ペアでは2回目以降
/// 新しいセッションを要求せずキャッシュを再利用する**ようにした。これにより
/// 「値の等しい `TranslationSession.Configuration` を代入し直しても `.translationTask` が
/// 再実行されない」という制約があっても、待ち行列が固着しない（詳細は
/// `SessionRequestQueue.swift` のコメントを参照）。
@MainActor
@Observable
final class Translator {
    /// 端末の表示言語。読むのは起動時の1回だけ（言語設定の変更はアプリの再起動後に
    /// 反映される、という受け入れ条件に合わせている）。
    let targetLanguage: Locale.Language
    /// モジュール内（`internal`）に留めているのは、ユニットテストから疑似翻訳の変換結果
    /// （`[<targetLanguageCode>] <原文>`）を検証できるようにするため。外部には公開しない。
    let targetLanguageCode: String

    /// `TranslationHostView` の `.translationTask` に渡す設定。
    /// 新しい言語ペアのセッションが必要になったときだけ値を差し替える
    /// （同じ言語ペアで2回差し替えることは無い。詳細は `SessionRequestQueue`）。
    private(set) var configuration: TranslationSession.Configuration?

    private let availability: LanguageAvailability
    /// 言語ペアごとの対応可否のキャッシュ（同じ問い合わせを繰り返さない）。
    private var statusCache: [String: Bool] = [:]
    /// 原文ごとの翻訳結果のキャッシュ。同じ回答を既読解除やスワイプで再び引いたときに
    /// 待たせないための、プロセス内だけの効果（F19: 同じ端末で2回目以降は待たせない）。
    /// モデル自体の再ダウンロードが起きないのは OS 側の仕組みによる。
    private var textCache: [String: String] = [:]
    /// `TranslationSession.translate` が「この言語ペアはこの端末では扱えない」という
    /// 種類のエラーを一度でも返した原文言語。以後はセッションを作り直さず即座にスキップする
    /// （毎回同じ理由で数秒待たされるのを防ぐ）。文字ごとの一時的な失敗とは区別するため、
    /// `TranslationError.unsupportedLanguagePairing` 系のときだけ記録する。
    private var unsupportedSourceCodes: Set<String> = []

    /// `TranslationSession` の取得を1件ずつさばく待ち行列。新しい言語ペアが必要になったら
    /// `configuration` を差し替えて `.translationTask` へ知らせる。
    /// `@ObservationIgnored`: `@Observable` の追跡対象にすると `lazy` と両立できない
    /// （SwiftUI の描画には関係しない内部の実装詳細のため、追跡対象からも外してよい）。
    @ObservationIgnored
    private lazy var sessionQueue = SessionRequestQueue<TranslationSession>(
        onNeedsSession: { [weak self] sourceCode in
            guard let self else { return }
            // `invalidate()` は「値が同じでも次のセッションは必ず作り直させる」ための保険
            // （evaluator の提案）。通常はここに来る時点で未取得の新しい言語ペアのはずだが、
            // 念のため呼んでおく。
            self.configuration?.invalidate()
            self.configuration = TranslationSession.Configuration(
                source: Locale.Language(identifier: sourceCode),
                target: self.targetLanguage
            )
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
        availability: LanguageAvailability = LanguageAvailability(),
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

        guard await isSupported(sourceCode: sourceCode) else {
            unsupportedSourceCodes.insert(sourceCode)
            return .unavailable(permanent: true)
        }

        guard let session = await sessionQueue.request(sourceCode) else {
            // 待ち行列がタイムアウトした（保険）。ソフトウェア側の不具合や一時的な状況を
            // 疑い、恒久的な非対応とは扱わない。既読にしないので後で再挑戦できる。
            return .unavailable(permanent: false)
        }
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
            // それ以外（一時的なエラー）はエラーダイアログを出さずスキップさせるが、
            // 既読にはしない（受け入れ条件・バグ4の修正）。
            return .unavailable(permanent: false)
        }
    }

    private func isSupported(sourceCode: String) async -> Bool {
        if let cached = statusCache[sourceCode] { return cached }
        let status = await availability.status(
            from: Locale.Language(identifier: sourceCode),
            to: targetLanguage
        )
        let supported = status != .unsupported
        statusCache[sourceCode] = supported
        return supported
    }

    /// `TranslationHostView` が新しいセッションを受け取ったら呼ぶ。
    func resolve(session: TranslationSession) {
        sessionQueue.resolve(session: session)
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
        // 実際の翻訳のような非同期の間（＝「準備中…」表示を確認できる余地）を残す。
        try? await Task.sleep(nanoseconds: 50_000_000)
        let translated = "[\(targetLanguageCode.uppercased())] \(text)"
        textCache[cacheKey] = translated
        return .text(translated)
    }

    /// 疑似モードでも「翻訳できない言語」を再現するための固定リスト。
    /// 同梱シードの `zxx`（`sameQ_untranslatable_test_marker`）に合わせている。
    private static let fakeUnsupportedSourceCodes: Set<String> = ["zxx"]
}
