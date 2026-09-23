import Foundation

/// 世界共通のお題（F03 / F09）。
///
/// 有効期間は開始・終了日時で表す。既定は28時間（置いた前提2）で、
/// 同時に有効なお題は常に1つだけ（置いた前提3）。期間外の時間帯はお題待ち画面になる。
struct Prompt: Codable, Identifiable, Equatable, Sendable {
    /// 世界共通の ID（例: prompt_001）
    let id: String
    /// お題の原文。画面には `AppSession.promptDisplayText`（端末言語へ翻訳済み）を出す（F22）。
    let text: String
    /// 有効期間の開始。これより前は「まだ始まっていない」。
    let startsAt: Date
    /// 有効期間の終了。この時刻を過ぎるとお題も回答も見えなくなる（F10）。
    let endsAt: Date
    /// お題原文の言語。`Post.bodyLanguage` と同じく、翻訳可否の判定にのみ内部利用する（F22）。
    let language: String
    /// 手書きの英語原文（あれば）。日本語以外の端末では機械翻訳を優先し、翻訳が
    /// `.unavailable` のときだけこれを予備として表示する（スプリント23）。
    /// 後方互換のため optional。旧バージョンでエンコードされたデータや
    /// `text_en` を持たないソースをデコードしても失敗しないよう、
    /// `decodeIfPresent` で読む（`Codable` の自動合成が optional プロパティを
    /// 欠損キー扱いで許容する挙動に依存）。
    let textEn: String?

    /// 標準の有効期間（置いた前提2）。
    static let defaultDuration: TimeInterval = 28 * 60 * 60

    init(id: String, text: String, startsAt: Date, endsAt: Date, language: String = "ja", textEn: String? = nil) {
        self.id = id
        self.text = text
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.language = language
        self.textEn = textEn
    }

    /// `date` の時点で有効か。終了時刻ちょうどは「終了済み」として扱う。
    func isActive(at date: Date) -> Bool {
        date >= startsAt && date < endsAt
    }
}
