import Foundation

/// 禁止表現の判定（F48）。
///
/// App Store ガイドライン 1.2 が求める「不適切なコンテンツをフィルタする仕組み」の
/// 端末側の担当。回答本文とニックネームの両方を見る。
///
/// **端末側とサーバー側の両方に同じ辞書を置く**（置いた前提35）。
/// 端末側は「書いている本人にその場で気づかせる」役、サーバー側
/// （`supabase/migrations/20260909000001_sprint20_ugc_safety.sql` の
/// `prohibited_terms` テーブル）は「アプリの画面を通さない経路で送られても
/// 保存させない」役で、どちらか一方では役目が足りない。
///
/// **どの語に当たったかは呼び出し側にも返さない**（置いた前提36）。
/// 返すのは「含むかどうか」だけ。理由を出すと、どう書き換えれば通るかの
/// 手掛かりになるため。
///
/// 辞書に語を足すときは、必ず SQL 側の `prohibited_terms` にも同じ語を足すこと。
enum ContentFilter {

    /// 照合の仕方。日本語と英語で分けるのが要点（置いた前提34）。
    enum MatchMode {
        /// 語境界での一致。ラテン文字の語に使う。
        /// 部分一致にすると `class` / `passed` / `analysis` / `title` のような
        /// 無関係な語が巻き込まれ、ふつうの投稿ができなくなる。
        case word
        /// 部分一致。日本語には語の区切りが無いので、こちらでないと素通りする。
        case substring
    }

    struct Term {
        let value: String
        let mode: MatchMode

        init(_ value: String, _ mode: MatchMode) {
            self.value = value
            self.mode = mode
        }
    }

    /// 本文・ニックネームが禁止表現を含むか。
    /// - Parameter text: 判定する文字列。前後の空白は呼び出し側で除去していなくてよい。
    static func containsProhibitedTerm(_ text: String) -> Bool {
        let normalized = normalized(text)
        guard !normalized.isEmpty else { return false }

        for term in terms {
            switch term.mode {
            case .substring:
                if normalized.contains(term.value) { return true }
            case .word:
                if containsAsWord(term.value, in: normalized) { return true }
            }
        }
        return false
    }

    // MARK: 正規化

    /// 照合前に表記の揺れを潰す。
    ///
    /// * 互換分解つき正規化（NFKC 相当）で全角英字 `Ｆｕｃｋ` や半角カナを標準形へ
    /// * 小文字化で大文字小文字を吸収
    ///
    /// カタカナ／ひらがなの揺れは、辞書側に両方の表記を持たせて吸収する
    /// （SQL 側と同じ手当てにして、端末とサーバーで判定がずれないようにするため）。
    static func normalized(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    /// `term` が語として現れるか。前後がラテン文字・数字なら語の一部とみなして数えない。
    ///
    /// 正規表現を使わないのは、辞書の語に含まれうるメタ文字のエスケープ漏れを
    /// 構造的に無くすため。
    private static func containsAsWord(_ term: String, in text: String) -> Bool {
        guard !term.isEmpty else { return false }

        var searchStart = text.startIndex
        while let range = text.range(of: term, range: searchStart..<text.endIndex) {
            let beforeIsWord: Bool = {
                guard range.lowerBound > text.startIndex else { return false }
                let previous = text[text.index(before: range.lowerBound)]
                return isWordCharacter(previous)
            }()
            let afterIsWord: Bool = {
                guard range.upperBound < text.endIndex else { return false }
                return isWordCharacter(text[range.upperBound])
            }()

            if !beforeIsWord && !afterIsWord { return true }

            // 語の一部だったので、次の出現を探す。
            searchStart = text.index(after: range.lowerBound)
            if searchStart >= text.endIndex { break }
        }
        return false
    }

    /// 語を構成する文字か。ラテン文字と数字だけを「語の一部」とみなす。
    /// 日本語の文字を含めないのは、日本語の文中に置かれた英単語
    /// （例:「今日は class の話」）を正しく語として切り出すため。
    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber)
    }

    // MARK: 辞書

    /// SQL 側 `prohibited_terms` の初期シードと同じ内容。
    /// 片方だけを更新しないこと（前提35）。
    static let terms: [Term] = [
        // 英語: 性的
        Term("fuck", .word),
        Term("fucking", .word),
        Term("fucker", .word),
        Term("motherfucker", .word),
        Term("cunt", .word),
        Term("dick", .word),
        Term("cock", .word),
        Term("pussy", .word),
        Term("blowjob", .word),
        Term("handjob", .word),
        Term("creampie", .word),
        Term("porn", .word),
        Term("porno", .word),
        Term("pornhub", .word),
        Term("hentai", .word),
        Term("nudes", .word),
        Term("boobs", .word),
        Term("tits", .word),
        Term("anal", .word),
        Term("jerk off", .substring),
        Term("cum", .word),
        // 英語: 侮蔑・差別
        Term("bitch", .word),
        Term("bastard", .word),
        Term("asshole", .word),
        Term("retard", .word),
        Term("retarded", .word),
        Term("nigger", .word),
        Term("nigga", .word),
        Term("faggot", .word),
        Term("tranny", .word),
        Term("chink", .word),
        Term("spic", .word),
        Term("kike", .word),
        Term("gook", .word),
        Term("wetback", .word),
        Term("raghead", .word),
        Term("subhuman", .word),
        // 英語: 暴力・自傷の扇動
        Term("kill yourself", .substring),
        Term("kys", .word),
        Term("go die", .substring),
        Term("i will kill you", .substring),
        Term("rape", .word),
        Term("rapist", .word),
        Term("lynch", .word),
        Term("genocide", .word),
        // 英語: 犯罪の助長
        Term("child porn", .substring),
        Term("cp trade", .substring),
        Term("buy drugs", .substring),
        Term("sell drugs", .substring),
        Term("meth for sale", .substring),
        Term("cocaine for sale", .substring),
        Term("hitman", .word),
        // 日本語: 暴力・侮蔑・差別
        Term("死ね", .substring),
        Term("しね", .substring),
        Term("氏ね", .substring),
        Term("殺す", .substring),
        Term("ころす", .substring),
        Term("殺してやる", .substring),
        Term("自殺しろ", .substring),
        Term("消えろ", .substring),
        Term("キチガイ", .substring),
        Term("きちがい", .substring),
        Term("気違い", .substring),
        Term("池沼", .substring),
        Term("知障", .substring),
        Term("土人", .substring),
        Term("部落民", .substring),
        Term("穢多", .substring),
        Term("非人", .substring),
        Term("チョン", .substring),
        Term("シナ人", .substring),
        Term("支那人", .substring),
        Term("在日認定", .substring),
        Term("ゴキブリども", .substring),
        Term("カタワ", .substring),
        Term("かたわ", .substring),
        Term("めくら", .substring),
        Term("つんぼ", .substring),
        // 日本語: 性的
        Term("セックス", .substring),
        Term("せっくす", .substring),
        Term("童貞", .substring),
        Term("処女膜", .substring),
        Term("ちんこ", .substring),
        Term("チンコ", .substring),
        Term("ちんぽ", .substring),
        Term("まんこ", .substring),
        Term("マンコ", .substring),
        Term("おっぱい揉", .substring),
        Term("射精", .substring),
        Term("中出し", .substring),
        Term("アへ顔", .substring),
        Term("エロ画像", .substring),
        Term("エロ動画", .substring),
        Term("無修正", .substring),
        Term("援交", .substring),
        Term("援助交際", .substring),
        Term("パパ活募集", .substring),
        Term("風俗嬢", .substring),
        Term("レイプ", .substring),
        Term("強姦", .substring),
        Term("痴漢", .substring),
        Term("児童ポルノ", .substring),
        // 日本語: 犯罪の助長
        Term("闇バイト", .substring),
        Term("裏バイト", .substring),
        Term("覚醒剤", .substring),
        Term("大麻売", .substring),
        Term("大麻買", .substring),
        Term("拳銃売", .substring),
        Term("爆弾の作り方", .substring),
        Term("殺人依頼", .substring),
        Term("口座売買", .substring),
        Term("名義貸し募集", .substring),
        // 連絡先・外部誘導（個人情報の記載＝規約の禁止事項、スパム対策）
        Term("http://", .substring),
        Term("https://", .substring),
        Term("www.", .substring),
        // `line id` を部分一致にすると "on|line id|ea"（online idea）を巻き込む。
        Term("line id", .word),
        Term("ラインid", .substring),
        Term("カカオid", .substring),
    ]
}
