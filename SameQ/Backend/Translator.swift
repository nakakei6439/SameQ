import Foundation
import Translation

/// 投稿本文とお題本文を端末言語へ変換する窓口（F18 / F20 / F21 / F22）。
///
/// Apple Translation Framework のみを使う（外部翻訳API・フォールバックは使わない。
/// 翻訳のために本文をサーバーへ送ることも無い。すべて端末内で完結する）。
///
/// `TranslationSession` は SwiftUI の `.translationTask` 修飾子からしか作れないため、
/// アプリのルートに常駐させた `TranslationHostView`（不可視）がセッションを供給する。
/// 呼び出し側（`AppSession`）はこの仕組みを意識せず `translate(_:sourceLanguageCode:)` を
/// 呼ぶだけでよい。
@MainActor
@Observable
final class Translator {
    /// 端末の表示言語。読むのは起動時の1回だけ（言語設定の変更はアプリの再起動後に
    /// 反映される、という受け入れ条件に合わせている）。
    let targetLanguage: Locale.Language
    private let targetLanguageCode: String

    /// `TranslationHostView` の `.translationTask` に渡す設定。
    /// 値が変わるたびに新しい `TranslationSession` が作られ、`resolve(session:)` が呼ばれる。
    private(set) var configuration: TranslationSession.Configuration?

    private let availability: LanguageAvailability
    /// 言語ペアごとの対応可否のキャッシュ（同じ問い合わせを繰り返さない）。
    private var statusCache: [String: Bool] = [:]
    /// 原文ごとの翻訳結果のキャッシュ。同じ回答を既読解除やスワイプで再び引いたときに
    /// 待たせないための、プロセス内だけの効果（F21: 同じ端末で2回目以降は待たせない）。
    /// モデル自体の再ダウンロードが起きないのは OS 側の仕組みによる。
    private var textCache: [String: String] = [:]
    /// `TranslationSession.translate` が「この言語ペアはこの端末では扱えない」という
    /// 種類のエラーを一度でも返した原文言語。以後はセッションを作り直さず即座にスキップする
    /// （毎回同じ理由で数秒待たされるのを防ぐ）。文字ごとの一時的な失敗とは区別するため、
    /// `TranslationError.unsupportedLanguagePairing` 系のときだけ記録する。
    private var unsupportedSourceCodes: Set<String> = []

    private struct PendingRequest {
        let source: Locale.Language
        let continuation: CheckedContinuation<TranslationSession, Never>
    }
    /// 翻訳要求を1つずつ順番にさばく（同時に複数投げても `.translationTask` の
    /// セッションを取り違えないようにするため）。
    private var pending: [PendingRequest] = []
    private var isSessionInFlight = false

    /// `nonisolated` にしているのは、`AppSession.init` の既定引数
    /// （`translator: Translator = Translator()`）として呼べるようにするため。
    /// 中身はどれも `Sendable` な値の代入だけで、MainActor 隔離のプロパティには触れない。
    nonisolated init(availability: LanguageAvailability = LanguageAvailability()) {
        self.availability = availability
        // `Locale.current.language` は使わない。このアプリは Localizable.strings 等の
        // 言語リソースを1つも持たないため、`Locale.current` は端末の言語設定を無視して
        // 開発言語（既定 "en"）に丸められることがある（実機・シミュレータで確認済みの挙動、
        // 例: 端末設定が日本語でも `Locale.current.identifier` が "en_JP" になる）。
        // アプリのローカライズ有無に左右されない `Locale.preferredLanguages`
        // （端末設定そのままの優先言語リスト）の先頭を「端末の言語」として使う。
        let preferredIdentifier = Locale.preferredLanguages.first ?? "en"
        let language = Locale.Language(identifier: preferredIdentifier)
        self.targetLanguage = language
        self.targetLanguageCode = (language.languageCode?.identifier ?? "en").lowercased()
    }

    /// `text` を端末言語へ翻訳する。
    ///
    /// - 原文の言語が端末言語と同じなら、翻訳せずそのまま返す（余計な待ちを作らない）。
    /// - 翻訳できない言語ペア、または翻訳に失敗した場合は `nil` を返す。
    ///   呼び出し側はこれを「表示しない（スキップする）」の合図として使う（F20）。
    func translate(_ text: String, sourceLanguageCode: String) async -> String? {
        guard !text.isEmpty else { return text }
        let sourceCode = sourceLanguageCode.lowercased()
        if sourceCode == targetLanguageCode { return text }

        let cacheKey = "\(sourceCode)\u{0}\(text)"
        if let cached = textCache[cacheKey] { return cached }
        guard !unsupportedSourceCodes.contains(sourceCode) else { return nil }

        guard await isSupported(sourceCode: sourceCode) else { return nil }

        let session = await requestSession(sourceCode: sourceCode)
        do {
            let response = try await session.translate(text)
            textCache[cacheKey] = response.targetText
            return response.targetText
        } catch {
            if TranslationError.unsupportedLanguagePairing ~= error
                || TranslationError.unsupportedSourceLanguage ~= error {
                unsupportedSourceCodes.insert(sourceCode)
            }
            // エラーダイアログは出さず、呼び出し側にスキップさせる（受け入れ条件）。
            return nil
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

    /// `TranslationSession` を1つ受け取る。`TranslationHostView` が
    /// `configuration` の変更を検知してセッションを作り、`resolve(session:)` で返してくる。
    private func requestSession(sourceCode: String) async -> TranslationSession {
        await withCheckedContinuation { continuation in
            pending.append(
                PendingRequest(source: Locale.Language(identifier: sourceCode), continuation: continuation)
            )
            startNextIfNeeded()
        }
    }

    private func startNextIfNeeded() {
        guard !isSessionInFlight, let next = pending.first else { return }
        isSessionInFlight = true
        configuration = TranslationSession.Configuration(source: next.source, target: targetLanguage)
    }

    /// `TranslationHostView` が新しいセッションを受け取ったら呼ぶ。
    func resolve(session: TranslationSession) {
        guard !pending.isEmpty else { return }
        let next = pending.removeFirst()
        isSessionInFlight = false
        next.continuation.resume(returning: session)
        startNextIfNeeded()
    }
}
