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
/// 対応（attempt 4時点）: `.installed` のときだけ `session.translate(_:)` まで進む。
/// `.supported`（未ダウンロード）のときは `session.translate(_:)` を呼ばず、
/// `.unavailable(permanent: false)`（一時的な失敗）として読み飛ばしていた。
/// この結果、対象言語のモデルが端末に無い回答は永久に表示されず、受け入れ条件4
/// （モデル未取得時は初回のみ準備中表示→取得後に読める）を満たせないと判定された
/// （eval-4.md [1]）。
///
/// ## attempt 5 での変更（eval-4.md [1] の修正・ユーザー承認済みでダウンロードを能動的に行う）
/// `.supported` を検出したら `session.prepareTranslation()` を明示的に呼び、モデルを
/// 能動的にダウンロードしてから翻訳する（`prepareIfNeeded(sourceLanguageCode:)`）。
///
/// `prepareTranslation()` はモデル未取得なら `translate(_:)` と同じ「翻訳／必要な
/// ダウンロード」確認シートを表示しうる（Apple Developer Forums のスレッド783311で
/// DTSエンジニアが明言: 「すでにインストール済み・ダウンロード中ならシートを出さずに
/// 返る」＝未取得なら出る、が前提）。この事実自体は attempt 4 の判断（[prepareTranslation()
/// を呼んでも同じ問題が残る]）どおりで変わっていない。attempt 4 との違いは**呼ぶ場所**:
/// `AppSession.openTimeline()` が、世界タイムライン（`fullScreenCover`）を**開く前**、
/// まだ今日のお題画面（非モーダル）にいる段階でこの準備を済ませる設計にした。
/// シートが出るとしても、そのとき画面上には畳まれて困る `fullScreenCover` が存在しない
/// （attempt 3 の致命的症状は「シートの下で `fullScreenCover` が閉じる」ことだったので、
/// その `fullScreenCover` を出す前に片付けてしまえば起こりようがない）。
/// タイムラインを開いたあとは、その時点で候補に挙がっている全言語のモデル取得を試み終えて
/// いるはずなので、`drawNextPost` が `.supported` に当たること自体がほぼ無くなる
/// （待ってもモデルが揃わなかった場合の保険として、`.installed` にならなかった言語は
/// 従来どおり `.unavailable(permanent: false)` で読み飛ばし、次回の巡回・次回起動で
/// 再挑戦できるようにする。既読にはしない）。
/// `session.prepareTranslation()` にも `sessionQueue` のタイムアウト機構
/// （`modelPrepareJobTimeoutSeconds`、既定60秒）を適用し、ダウンロードが長引く・失敗する
/// 場合でも画面が固まらないようにする。
///
/// ## attempt 6 での変更（eval-5.md [1][2] の修正）
/// attempt 5 は「試して失敗した」を一切覚えなかったため、モデル未ダウンロードの言語が
/// 候補に残っている限り、**タイムラインを開くたびに毎回**同じ60〜120秒の待ちが発生した
/// （実機実測: round1 62.1秒 / round2 61.3秒。`eval-5.md` [1]）。
/// `lastPrepareAttemptAt` に「この言語を最後に試みた時刻」を記録し、
/// `modelDownloadRetryCooldownSeconds`（既定5分）以内の再試行は行わない
/// （`shouldAttemptPreparation`）。「毎回律儀に試す」と「一度失敗したら二度と試さない」の
/// 中間を取った: 5分経てば次にタイムラインを開いたときに再挑戦できるので、モデルの
/// ダウンロードが裏で完了していれば（あるいは電波状況が変わっていれば）いずれ読めるように
/// なる可能性を残しつつ、直後の再オープンでは待たせない。
/// `AppSession.prepareTimelineLanguagesIfNeeded` はこの判定を `needsPreparation` で
/// 事前に確認し、実際に試みる言語が1つも無ければ `isPreparingTimeline` すら立てない
/// （ボタンの「準備中…」が一瞬もちらつかない）。
///
/// また `submit()`（`AppSession`）が `openTimeline()` の完了を待たなくなったため、
/// 投稿ボタンがモデルダウンロードの待ち時間を背負わなくなった（詳細は `AppSession.submit`）。
///
/// ## attempt 7 での変更（eval-6.md [1] の修正）
/// attempt 6 の `lastPrepareAttemptAt` はこのインスタンスのプロセス内メモリにしか
/// 無かった。`AppSession` は起動のたびに既定引数で新しい `Translator` を作り直すため、
/// アプリを終了して開き直すと「最後に試した時刻」の記録がゼロから始まり、実時間では
/// クールダウン中（既定5分未満）でも同じ約60〜67秒の待ちが再発することが実機で確認された
/// （eval-6.md「実測2」）。
///
/// `attemptPersistence`（`TranslationAttemptPersisting`。実体は `AppSession` が持つのと
/// 同じ `Backend` インスタンス）へ、試みた時刻を都度書き込むようにした。読む側は
/// プロセス内で一度でも触った言語なら（成功・失敗どちらでも）メモリの値を正とし、
/// まだ一度も触っていない言語だけ、起動直後の1回に限って永続化された値を取り込む
/// （`hydrateLastPrepareAttemptIfNeeded`）。書き込みは常に `Backend`（アクター）を
/// 経由するので、`LocalBackend` が持つメモリ上のスナップショットと競合して片方の
/// 書き込みが失われる、という事態にはならない（`Translator` 自身が `LocalStore` へ
/// 直接読み書きしない設計上の理由は `TranslationAttemptPersisting` のコメントを参照）。
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
    /// 疑似モード（`-SameQFakeTranslate`）専用: `fakePrepareIfNeeded` が「ダウンロード完了」を
    /// 模擬した言語コード（`qtd`）。実際の `LanguageAvailability` を持たない疑似モードでは
    /// `statusCache` の代わりにこれで「もう準備中の対象ではない」ことを覚える（attempt 5）。
    private var fakeDownloadedSourceCodes: Set<String> = []
    /// 言語ごとに「最後にダウンロードを試みた時刻」。`.supported` のままダウンロードが
    /// 完了しなかった言語を、`modelDownloadRetryCooldownSeconds` の間は再試行しないために使う
    /// （eval-5.md [1]: 毎回ゼロから同じ待ちを繰り返す問題の修正。attempt 6）。
    private var lastPrepareAttemptAt: [String: Date] = [:]
    /// `lastPrepareAttemptAt` を `attemptPersistence` から取り込み済みの言語コード
    /// （attempt 7）。1プロセスにつき言語ごとに1回だけ問い合わせれば十分なので、
    /// 一度取り込んだ（または「まだ一度も試みていない」と分かった）言語は再問い合わせしない。
    private var hydratedFromPersistenceSourceCodes: Set<String> = []
    /// `lastPrepareAttemptAt` を `state.json` 経由でアプリの終了・再起動をまたいで
    /// 永続化するための窓口（attempt 7: eval-6.md [1] の修正）。`nil` なら従来どおり
    /// プロセス内メモリだけで完結する（ユニットテストの多くはこれで十分なため既定は nil）。
    private let attemptPersistence: TranslationAttemptPersisting?

    /// `sessionQueue` のセッション取得タイムアウト（`translate` にも `prepareIfNeeded` にも
    /// 共通で使う。ユニットテストでは短く差し替えて、解決されないまま待たされることを防ぐ）。
    private let sessionAcquireTimeoutSeconds: Double
    /// `session.translate(_:)` 自体のタイムアウト（従来どおり）。
    private let sessionJobTimeoutSeconds: Double
    /// `session.prepareTranslation()`（モデルのダウンロード）自体のタイムアウト。
    /// ダウンロードは通常の翻訳より時間が掛かりうるため、別の長さを持つ（attempt 5）。
    private let modelPrepareJobTimeoutSeconds: Double
    /// ダウンロードを試みて `.supported` のまま完了しなかった言語を、次に再試行するまで
    /// 空ける間隔（既定5分）。この間はダウンロードを試みず、既存の一時的失敗として
    /// 静かに読み飛ばす（eval-5.md [1]。attempt 6）。
    private let modelDownloadRetryCooldownSeconds: Double
    /// 「今」を読む窓口。ユニットテストが `lastPrepareAttemptAt` との経過時間を制御できるように
    /// 差し替え可能にしている（既定は実時計）。
    private let now: () -> Date

    /// `TranslationSession` の取得を1件ずつさばく待ち行列。新しいセッションが必要になる
    /// たびに（同じ言語ペアでも毎回）`configuration` を更新して `.translationTask` へ知らせる。
    /// `@ObservationIgnored`: `@Observable` の追跡対象にすると `lazy` と両立できない
    /// （SwiftUI の描画には関係しない内部の実装詳細のため、追跡対象からも外してよい）。
    @ObservationIgnored
    private lazy var sessionQueue = SessionRequestQueue<TranslationSession>(
        acquireTimeoutSeconds: sessionAcquireTimeoutSeconds,
        jobTimeoutSeconds: sessionJobTimeoutSeconds,
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
    /// - Parameters:
    ///   - preferredLanguageIdentifier: 通常は指定しない（`Locale.preferredLanguages`
    ///     を読む）。ユニットテストがホスト環境のロケールに関係なく決定的に検証できるように、
    ///     端末の言語を上書きするための引数。
    ///   - sessionAcquireTimeoutSeconds: セッション取得自体のタイムアウト（既定45秒）。
    ///     ユニットテストは実際の `.translationTask` が無い環境で `.supported` の準備
    ///     （`prepareIfNeeded`）を検証するため、ここを短く差し替えて待たされないようにする。
    ///   - modelPrepareJobTimeoutSeconds: `session.prepareTranslation()`（モデルの
    ///     ダウンロード）自体のタイムアウト（既定60秒。`session.translate(_:)` の既定30秒より
    ///     長い。ダウンロードは翻訳そのものより時間が掛かりうるため）。
    ///   - modelDownloadRetryCooldownSeconds: ダウンロードを試みて `.supported` のまま
    ///     完了しなかった言語を、次に再試行するまで空ける間隔（既定5分）。ユニットテストは
    ///     `now` と合わせて短く／制御可能にして、クールダウンの境界を確定的に検証する。
    ///   - now: 「今」を読む窓口（既定は実時計）。ユニットテストが `lastPrepareAttemptAt`
    ///     からの経過時間を仮想的に進められるようにするための差し替え口。
    ///   - attemptPersistence: `lastPrepareAttemptAt` をアプリの終了・再起動をまたいで
    ///     永続化する窓口（既定は nil ＝プロセス内メモリのみ。attempt 7）。`AppSession` は
    ///     既定引数でこの `Translator` を作るとき、自分が使う `Backend` インスタンスを
    ///     そのまま渡す（詳細は `AppSession.init`）。
    nonisolated init(
        availability: LanguageAvailabilityProviding = LanguageAvailability(),
        fakeTranslate: Bool = LaunchOptions.current.fakeTranslate,
        preferredLanguageIdentifier: String? = nil,
        sessionAcquireTimeoutSeconds: Double = 45,
        sessionJobTimeoutSeconds: Double = 30,
        modelPrepareJobTimeoutSeconds: Double = 60,
        modelDownloadRetryCooldownSeconds: Double = 300,
        now: @escaping () -> Date = Date.init,
        attemptPersistence: TranslationAttemptPersisting? = nil
    ) {
        self.availability = availability
        self.fakeTranslateEnabled = fakeTranslate
        self.sessionAcquireTimeoutSeconds = sessionAcquireTimeoutSeconds
        self.sessionJobTimeoutSeconds = sessionJobTimeoutSeconds
        self.modelPrepareJobTimeoutSeconds = modelPrepareJobTimeoutSeconds
        self.modelDownloadRetryCooldownSeconds = modelDownloadRetryCooldownSeconds
        self.now = now
        self.attemptPersistence = attemptPersistence
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

    /// `sourceLanguageCode` のモデルがこの端末に無い（`.supported`）場合、能動的に
    /// ダウンロードを試みる（受け入れ条件4・attempt 5）。
    ///
    /// 呼び出し元（`AppSession.openTimeline()`）が、世界タイムライン（`fullScreenCover`）を
    /// **開く前**に呼ぶことを前提にした設計。OSの「翻訳／必要なダウンロード」確認シートが
    /// 出るとしても、そのときにはまだ畳んで困る `fullScreenCover` が存在しない（クラス冒頭の
    /// コメントを参照）。
    ///
    /// - `.installed`（既にダウンロード済み）・`.unsupported`（恒久的に非対応）・
    ///   端末言語と同じ、のいずれかならここでは何もしない（無駄なセッション要求をしない）。
    /// - `.supported` かつ、直近 `modelDownloadRetryCooldownSeconds` 以内に
    ///   このコードを試していなければ `session.prepareTranslation()` を呼ぶ。
    ///   クールダウン中なら**何も試みず即座に返る**（eval-5.md [1]: タイムラインを開くたびに
    ///   毎回ゼロから同じ待ちを繰り返す問題の修正。attempt 6）。
    /// - 失敗・タイムアウト（`modelPrepareJobTimeoutSeconds`）してもエラーは投げず、静かに
    ///   諦める。呼び出し元の `translate(_:sourceLanguageCode:)` は、それでもまだ
    ///   `.supported` のままなら従来どおり `.unavailable(permanent: false)` で読み飛ばす
    ///   （既読にしない＝クールダウンが明ければまた挑戦できる）。
    func prepareIfNeeded(sourceLanguageCode: String) async {
        let sourceCode = sourceLanguageCode.lowercased()
        guard await shouldAttemptPreparation(sourceCode: sourceCode) else { return }

        if fakeTranslateEnabled {
            await fakePrepareIfNeeded(sourceCode: sourceCode)
            return
        }

        // 実際に試みる直前に記録する（成功・失敗・タイムアウトのいずれでも「試した」ことに
        // なる。ここを更新しないと、失敗するたびに次のクールダウン判定が効かない）。
        let attemptedAt = now()
        lastPrepareAttemptAt[sourceCode] = attemptedAt
        // 以後この言語は「プロセス内で一度触った」ことになるので、次にこのプロセス内で
        // 判定するときはメモリの値をそのまま正として使い、永続化された値を読み直さない
        // （attempt 7）。
        hydratedFromPersistenceSourceCodes.insert(sourceCode)
        if let attemptPersistence {
            // アプリを終了して開き直しても、この「試した時刻」を次の `Translator` が
            // 引き継げるようにする（eval-6.md [1] の修正の核心）。失敗しても翻訳自体は
            // 続行してよいので `try?` で握りつぶす（クールダウンがプロセス内メモリだけに
            // 留まる旧来の挙動に戻るだけで、翻訳のスキップ判定そのものは壊れない）。
            try? await attemptPersistence.recordModelPrepareAttempt(sourceLanguageCode: sourceCode, at: attemptedAt)
        }
        _ = await sessionQueue.perform(
            key: sourceCode,
            jobTimeoutSeconds: modelPrepareJobTimeoutSeconds,
            body: { session -> Bool in
                do {
                    try await session.prepareTranslation()
                    return true
                } catch {
                    // ダウンロードの拒否・失敗はエラーを投げずに諦める。`translate(_:)` 側の
                    // `.supported` チェックが引き続き `.unavailable(permanent: false)` として
                    // 扱うので、利用者にエラーが見えることはない。
                    return false
                }
            },
            onJobTimeout: { session in
                if #available(iOS 26.0, *) {
                    session.cancel()
                }
            }
        )
    }

    /// `sourceLanguageCode` のダウンロードを**いま試みる価値があるか**を、実際には試みずに
    /// 判定する（`.supported` かつクールダウン中でない）。
    ///
    /// `AppSession.prepareTimelineLanguagesIfNeeded` はタイムラインを開く前に、この関数で
    /// 事前に「本当に試みる言語」を絞り込んでから `isPreparingTimeline` を立てる。全言語が
    /// クールダウン中（＝直近で試して駄目だった）なら `isPreparingTimeline` すら一度も
    /// true にならず、「世界の回答を読む」ボタンが「準備中…」に一瞬も変わらない
    /// （eval-5.md [1] の副次対応。attempt 6）。
    func needsPreparation(sourceLanguageCode: String) async -> Bool {
        await shouldAttemptPreparation(sourceCode: sourceLanguageCode.lowercased())
    }

    private func shouldAttemptPreparation(sourceCode: String) async -> Bool {
        guard sourceCode != targetLanguageCode else { return false }
        guard !unsupportedSourceCodes.contains(sourceCode) else { return false }

        if fakeTranslateEnabled {
            return Self.fakeNeedsDownloadSourceCodes.contains(sourceCode) && !fakeDownloadedSourceCodes.contains(sourceCode)
        }

        guard await availabilityStatus(sourceCode: sourceCode) == .supported else { return false }
        await hydrateLastPrepareAttemptIfNeeded(sourceCode: sourceCode)
        if let lastAttempt = lastPrepareAttemptAt[sourceCode],
           now().timeIntervalSince(lastAttempt) < modelDownloadRetryCooldownSeconds {
            return false
        }
        return true
    }

    /// このプロセスでまだ一度も触っていない言語について、`attemptPersistence` から
    /// 「最後に試した時刻」を1回だけ取り込む（attempt 7: eval-6.md [1] の修正）。
    ///
    /// アプリを終了して開き直すと `Translator` は新しいインスタンスとして作り直されるが
    /// （`AppSession` の既定引数）、その新しいインスタンスのメモリには何の記録も無い。
    /// ここで永続化された値を1回だけ読み込むことで、実時間ではまだクールダウン中の言語を
    /// 「まだ一度も試していない」と誤判定して、また待たせてしまうことを防ぐ。
    ///
    /// 一度取り込んだ（または「記録が無い」と分かった）言語は `hydratedFromPersistenceSourceCodes`
    /// に記録し、以後はこのプロセス内での判定を正として扱う（`attemptPersistence` への
    /// 問い合わせを言語ごとに何度も繰り返さないため）。
    private func hydrateLastPrepareAttemptIfNeeded(sourceCode: String) async {
        guard !hydratedFromPersistenceSourceCodes.contains(sourceCode) else { return }
        hydratedFromPersistenceSourceCodes.insert(sourceCode)
        guard let attemptPersistence else { return }
        if let persisted = try? await attemptPersistence.lastModelPrepareAttempt(sourceLanguageCode: sourceCode) {
            lastPrepareAttemptAt[sourceCode] = persisted
        }
    }

    /// 疑似モード（`-SameQFakeTranslate`）での `prepareIfNeeded` 相当。
    /// `qtd`（ダウンロード未取得を模擬する検証用マーカー）だけを対象に、実際の
    /// `TranslationSession` に一切触れず「ダウンロードが完了した」状態を記録する。
    /// これ以降の `translate(_:sourceLanguageCode:)` 呼び出しは、この言語を通常どおり
    /// 翻訳できる（＝「初回のみ準備中→完了後に読める」を疑似モードでも確定的に確認できる）。
    private func fakePrepareIfNeeded(sourceCode: String) async {
        guard Self.fakeNeedsDownloadSourceCodes.contains(sourceCode),
              !fakeDownloadedSourceCodes.contains(sourceCode) else { return }
        // 実際のダウンロード待ちを模した間（本番の「準備中…」表示を確認できる余地）。
        try? await Task.sleep(nanoseconds: 300_000_000)
        fakeDownloadedSourceCodes.insert(sourceCode)
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
        // （`.supported`）」を模擬する（attempt 4）。`fakePrepareIfNeeded` で「ダウンロード
        // 済み」を記録するまでは、実際の `TranslationSession` には一切触れず、OSのダウンロード
        // 確認シートを絶対に出さないことをシミュレータでも確定的に確認できるようにする
        // （eval-3.md [1] の再発防止）。`AppSession.openTimeline()` が能動的にダウンロードを
        // 試みたあと（attempt 5）は、`fakeDownloadedSourceCodes` に入り、以降は通常の翻訳
        // として扱う（＝「初回のみ準備中→完了後に読める」の確認）。
        if Self.fakeNeedsDownloadSourceCodes.contains(sourceCode), !fakeDownloadedSourceCodes.contains(sourceCode) {
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
