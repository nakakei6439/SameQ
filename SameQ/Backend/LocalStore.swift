import Foundation

/// 端末に永続化する内容。アカウント・自分の回答・自分のいいね・既読・通報・ブロックだけを持つ。
/// 他人の回答は同梱シード（`SeedCatalog`）側にあるので保存しない。
struct PersistedState: Codable, Sendable {
    var schemaVersion: Int
    var user: AppUser?
    var myPosts: [Post]
    var likedPostIDs: [UUID]
    /// 一度タイムラインに出した回答の ID（F12）。再起動しても同じ回答を出さないために残す。
    var viewedPostIDs: [UUID]
    /// 自分が出した通報（F13）。再起動しても通報した回答を出さないために残す。
    var reports: [Report]
    /// ブロック中の相手（F14 / F15）。解除するまで残る。
    var blockedAuthors: [BlockedAuthor]
    /// 直近に投稿した本文（F17: 同一文面の連投拒否）。
    /// `myPosts` は投稿の表示期限が切れると掃除されるが、こちらはお題をまたいで残す。
    var lastPostBody: String?
    /// 言語コード（小文字）ごとに「最後に翻訳モデルのダウンロードを試みた時刻」
    /// （受け入れ条件4・attempt 7: eval-6.md [1] の修正）。
    ///
    /// attempt 6 まではこれと同じ役割の `Translator.lastPrepareAttemptAt` がアプリの
    /// プロセス内メモリにしか無く、`Translator` は起動のたびに（`AppSession` が
    /// 既定引数で作り上げるため）ゼロから作られていた。そのため、実時間ではまだ
    /// クールダウン中（既定5分未満）でもアプリを終了して開き直すと記録が消え、
    /// モデル未ダウンロードの言語があるたびに毎回60秒超の「準備中…」を再び待たされる
    /// ことが実機で確認された（eval-6.md「実測2」）。ここに永続化することで、
    /// `Translator` が新しいインスタンスとして作り上げ直されても、同じ `Backend`
    /// （＝同じ `state.json`）を通じて直近の試行時刻を引き継げる。
    var lastPrepareAttemptAt: [String: Date]

    /// お題の自動生成（F26）で安全条件により破棄された候補の累計件数
    /// （受け入れ条件 4「破棄された記録が残る」）。
    ///
    /// UI には出さず、Debug オーバーレイ（`-SameQDebugOverlay`）で
    ///「discarded N」として確認できるようにするための積算値。
    /// 仕様は「記録が残る」を求めるだけで個別の破棄内容を
    /// ユーザーや運営に常時見せることは求めていないので、件数のみを
    /// 永続化する（個別候補のログはメモリ内にとどめて画面表示もしない）。
    var discardedCandidatesCount: Int

    /// Supabase の認証情報（アクセストークン・更新トークン・ユーザーID）。
    /// スプリント12で追加。`nil` のときは未認証、または `LocalBackend` を使っている。
    /// 既存ファイルにはこのキーが無いので、`decodeIfPresent` でフォールバックする。
    var supabaseAuth: SupabaseAuthState?

    /// 言語コード（小文字）ごとに「タイムラインで実際に表示した回数」
    /// （スプリント17・F41）。先読み対象の「直近よく出会う言語」を選ぶ材料で、
    /// 表示が確定した瞬間にインクリメントする（受け入れ条件1「直近よく出会う言語の
    /// 上位3件まで」）。`TopLevelEncoder` は JSON なのでキーは文字列、
    /// 値は Int（表示回数）。端末内のみ（F19「翻訳を意識させない」のため、
    /// サーバーには送らず、再インストールで消えても問題ない）。
    var languageEncounters: [String: Int]

    /// 同意した利用規約の版と日時（F53）。未同意なら nil。
    /// 版が `LegalText.version` と違うときは、起動時に再同意を求める（置いた前提42）。
    var termsAcceptance: TermsAcceptance?

    /// 2 で `viewedPostIDs`、3 で `reports` / `blockedAuthors`、4 で `lastPostBody`、
    /// 5 で `lastPrepareAttemptAt` を追加した。
    /// `discardedCandidatesCount` は 6 で追加したが、スキーマバージョンは据え置き
    ///（既存ファイルには値が無く、デフォルト 0 で埋めて互換性を保つ）。
    /// 6 で `Report.postExpiresAt` を追加したが、`Report.init(from:)` が
    /// `createdAt + 28h` でフォールバックするので、ユーザーデータの消失は無い
    /// （F34 安全ログの 30 日保持用）。
    /// 7 で `supabaseAuth` を追加（スプリント12・F35）。
    /// 8 で `languageEncounters` を追加（スプリント17・F41）。既存ファイルには
    /// キーが無いので `decodeIfPresent` でフォールバック（空辞書）。
    /// 9 で `Post.status`（F49 / F50）と `termsAcceptance`（F53）を追加。
    /// どちらも `decodeIfPresent` でフォールバックする（`Post.init(from:)` は
    /// 欠けている `status` を `.visible` として読む）ので、既存のアカウント・
    /// 回答・いいね・ブロックは消えない。
    static let currentSchemaVersion = 9

    static let empty = PersistedState(
        schemaVersion: currentSchemaVersion,
        user: nil,
        myPosts: [],
        likedPostIDs: [],
        viewedPostIDs: [],
        reports: [],
        blockedAuthors: [],
        lastPostBody: nil,
        lastPrepareAttemptAt: [:],
        discardedCandidatesCount: 0,
        supabaseAuth: nil,
        languageEncounters: [:],
        termsAcceptance: nil
    )

    init(
        schemaVersion: Int,
        user: AppUser?,
        myPosts: [Post],
        likedPostIDs: [UUID],
        viewedPostIDs: [UUID],
        reports: [Report] = [],
        blockedAuthors: [BlockedAuthor] = [],
        lastPostBody: String? = nil,
        lastPrepareAttemptAt: [String: Date] = [:],
        discardedCandidatesCount: Int = 0,
        supabaseAuth: SupabaseAuthState? = nil,
        languageEncounters: [String: Int] = [:],
        termsAcceptance: TermsAcceptance? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.user = user
        self.myPosts = myPosts
        self.likedPostIDs = likedPostIDs
        self.viewedPostIDs = viewedPostIDs
        self.reports = reports
        self.blockedAuthors = blockedAuthors
        self.lastPostBody = lastPostBody
        self.lastPrepareAttemptAt = lastPrepareAttemptAt
        self.discardedCandidatesCount = discardedCandidatesCount
        self.supabaseAuth = supabaseAuth
        self.languageEncounters = languageEncounters
        self.termsAcceptance = termsAcceptance
    }

    /// 旧バージョン（schemaVersion 1〜7）の保存ファイルにはキーが無いので、
    /// 欠けている項目は空として読む。アカウントを消さずに移行するため。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        user = try container.decodeIfPresent(AppUser.self, forKey: .user)
        myPosts = try container.decodeIfPresent([Post].self, forKey: .myPosts) ?? []
        likedPostIDs = try container.decodeIfPresent([UUID].self, forKey: .likedPostIDs) ?? []
        viewedPostIDs = try container.decodeIfPresent([UUID].self, forKey: .viewedPostIDs) ?? []
        reports = try container.decodeIfPresent([Report].self, forKey: .reports) ?? []
        blockedAuthors = try container.decodeIfPresent([BlockedAuthor].self, forKey: .blockedAuthors) ?? []
        lastPostBody = try container.decodeIfPresent(String.self, forKey: .lastPostBody)
        lastPrepareAttemptAt = try container.decodeIfPresent([String: Date].self, forKey: .lastPrepareAttemptAt) ?? [:]
        discardedCandidatesCount = try container.decodeIfPresent(Int.self, forKey: .discardedCandidatesCount) ?? 0
        supabaseAuth = try container.decodeIfPresent(SupabaseAuthState.self, forKey: .supabaseAuth)
        languageEncounters = try container.decodeIfPresent([String: Int].self, forKey: .languageEncounters) ?? [:]
        termsAcceptance = try container.decodeIfPresent(TermsAcceptance.self, forKey: .termsAcceptance)
    }
}

/// 利用規約への同意の記録（F53）。
///
/// Apple のガイドライン 1.2 は「利用規約への同意を求めること」を要求している。
/// 同意した事実が端末に残っていないと、規約を改定したときに既存の利用者へ
/// 読ませ直す判断ができない（置いた前提42）。
struct TermsAcceptance: Codable, Equatable, Sendable {
    /// 同意した規約の版（`LegalText.version` と同じ文字列）。
    let version: String
    let acceptedAt: Date
}

/// `PersistedState` を JSON 1ファイルとして読み書きする。
///
/// 書き込みは常に「まるごと1回で置き換える」。初回設定の途中で落ちても
/// 中途半端なアカウントが残らないように、保存はアカウント確定時にしか呼ばない。
struct LocalStore: Sendable {
    private let fileURL: URL

    init(fileName: String = "state.json") {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL.temporaryDirectory
        let directory = base.appendingPathComponent("SameQ", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        self.fileURL = directory.appendingPathComponent(fileName, isDirectory: false)
    }

    func load() -> PersistedState {
        guard let data = try? Data(contentsOf: fileURL) else { return .empty }
        guard let state = try? Self.decoder.decode(PersistedState.self, from: data) else {
            // 壊れたファイルを読んで起動不能になるより、初回設定からやり直す方が安全。
            return .empty
        }
        return state
    }

    func save(_ state: PersistedState) throws {
        do {
            // 旧バージョンから読み込んだ状態でも、書き戻した時点で現在のバージョンに揃える
            // （揃えないと、次の移行で「まだ旧形式」と誤判定する）。
            var state = state
            state.schemaVersion = PersistedState.currentSchemaVersion
            let data = try Self.encoder.encode(state)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            throw BackendError.storageFailure(error.localizedDescription)
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// 永続化する Supabase 認証情報（スプリント12）。
/// `PersistedState.supabaseAuth` に格納する。`LocalStore.swift` に置くのは、
/// `PersistedState` の Codable として同じファイルで扱えるようにするため
/// （`Backend` プロトコル本体には依存させたくない）。
struct SupabaseAuthState: Codable, Sendable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let userID: UUID
    let createdAt: Date
}
