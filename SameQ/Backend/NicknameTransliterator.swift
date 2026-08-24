import Foundation

/// ニックネームを閲覧者の文字体系へ音写する純関数（F23）。
///
/// 意味翻訳ではなく**音写（transliteration）**である点が重要。
/// `String.applyingTransform(_:reverse:)` の `kCFStringTransform*` 系だけを
/// 組み合わせるので、外部翻訳APIや Translation Framework は使わない（翻訳と直交する
/// 軽い処理で、投稿本文やお題の翻訳とは独立に動く）。
///
/// ## アルゴリズム
/// 1. 原文をいったん Latin へ音写（`Latin;` = `kCFStringTransformToLatin`）。
///    日本語 `景太` → `jing tai`、ハングル `케이타` → `keita`、キリル `Иван` → `Ivan`、
///    アラビア `محمد` → `mhmd` のように、たいていの文字体系はここで読める形になる。
/// 2. その Latin 表記を、端末言語の文字体系へ再音写
///    （`Latin-Katakana;` / `Latin-Hangul;` / `Latin-Arabic;` /
///     `Latin-Cyrillic;` / `Latin-Devanagari;` / `Latin-Hebrew;`）。
///    端末言語が既に Latin 系（`en` / `de` / `fr` …）のときはステップ2は省略する。
///
/// どの段階で変換できなかったり、変換後の文字列が空になったら `nil` を返す
/// （呼び出し側は「ニックネーム未設定」と同じ扱いにして、絵文字のみ表示にフォールバックする。
/// 受け入れ条件3）。
///
/// 端末言語と原文の**スクリプトが一致している**場合は、音写をスキップして原文をそのまま返す
/// （日本語端末で `景太` → `ジング タイ` のように**改悪**するのを避けるため。
/// 意味翻訳ではなく音写が目的である以上、原文が既に読める形ならそのまま出すのが正解）。
///
/// ## 受け入れ条件との関係
/// - **条件1（端末言語と異なる文字体系が端末言語の文字体系で表示される）**: 上記の2段書き換えで実現。
/// - **条件2（音写であり意味翻訳された言葉にならない）**: `applyingTransform` は常に音写なので自然に満たされる。
/// - **条件3（音写できないニックネームは絵文字のみ）**: `nil` 返却 → 呼び出し側で絵文字のみ表示。
/// - **条件4（絵文字のみ表示でレイアウトが崩れない）**: 呼び出し側の既存 `displayNickname == nil` パスが
///   そのまま流れるので新規 UI 変更は不要。
/// - **条件5（自分のニックネームは原文のまま）**: 呼び出し側で `isOwn` を見て transliterator を
///   経由しない（`Post.displayedNickname(transliterator:isOwn:)` の `isOwn: true` で
///   `self.displayNickname` を返す）。
struct NicknameTransliterator: Sendable {
    /// 端末の表示言語コード（`ja` / `en` / `ko` / `ar` など、`Translator.targetLanguageCode` に揃える）。
    let targetLanguageCode: String

    /// Debug限定・起動引数 `-SameQNicknameTranslitDebug` の値。true の間は
    /// すべての入力に対して音写失敗扱いを返し、絵文字のみ表示へのフォールバックを
    /// 受け入れ条件3の検証用に再現できるようにする。
    let forceFailure: Bool

    init(targetLanguageCode: String, forceFailure: Bool = LaunchOptions.current.forceNicknameTranslitFailure) {
        self.targetLanguageCode = targetLanguageCode.lowercased()
        self.forceFailure = forceFailure
    }

    /// ニックネーム原文を端末言語の文字体系に音写する。音写できない場合は `nil`。
    ///
    /// 空白のみの文字列・空文字は最初から「ニックネーム未設定」と同じ扱い（`nil`）にする
    /// （呼び出し側の既存ロジックと挙動を合わせる）。
    ///
    /// 絵文字・記号・数字だけで構成された文字列も「名前」ではないので `nil` を返す
    /// （`Mizuki 🌙` のような末尾の絵文字は**そのまま通す**。絵文字だけの場合は表示すると
    /// ユーザー名の欄に絵文字が並ぶだけになるので、絵文字のみ表示に降ろす）。
    func transliterate(_ nickname: String?) -> String? {
        guard let nickname else { return nil }
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if forceFailure { return nil }
        // どのスクリプトにも属さない（絵文字・記号・数字のみ）文字列は nil。
        guard detectScript(of: trimmed) != nil else { return nil }

        // 原文のスクリプトが端末言語のスクリプトと一致しているなら、音写せず原文のまま返す。
        // 日本語端末の `景太` を `ジング タイ` に改悪しないため。
        let targets = targetScripts(for: targetLanguageCode)
        if !targets.isEmpty,
           targets.contains(where: { Self.script($0, contains: trimmed) })
        {
            return trimmed
        }

        // ステップ1: 原文 → Latin。失敗したら音写不能（絵文字のみ表示）として扱う。
        guard let latin = trimmed.applyingTransform(.toLatin, reverse: false),
              let stripped = latin.applyingTransform(.stripCombiningMarks, reverse: false),
              !stripped.isEmpty
        else { return nil }

        // ステップ2: Latin → 端末言語の文字体系。Latin 系端末では不要なのでそのまま返す。
        if let scriptTransform = latinScriptTransform(for: targetLanguageCode),
           let rendered = stripped.applyingTransform(scriptTransform, reverse: false),
           !rendered.isEmpty
        {
            return rendered
        }
        return stripped
    }

    /// 端末言語ごとに「Latin → 自文字体系」変換を返す。Latin 系（en/de/fr/...）は
    /// 変換不要なので `nil` を返し、呼び出し側でステップ2を省略する。
    private func latinScriptTransform(for code: String) -> StringTransform? {
        switch code {
        case "ja":
            // 日本語端末では `Latin-Katakana` でカタカナ音写する（日本語ユーザーは
            // カタカナの読み慣れた名前表記を好むため。Latin-Hiragana だと細かすぎる）。
            return StringTransform(rawValue: "Latin-Katakana")
        case "ko":
            return StringTransform(rawValue: "Latin-Hangul")
        case "ar":
            return StringTransform(rawValue: "Latin-Arabic")
        case "ru", "uk", "be":
            return StringTransform(rawValue: "Latin-Cyrillic")
        case "hi", "mr", "ne":
            return StringTransform(rawValue: "Latin-Devanagari")
        case "he":
            return StringTransform(rawValue: "Latin-Hebrew")
        case "el":
            return StringTransform(rawValue: "Latin-Greek")
        case "th":
            return StringTransform(rawValue: "Latin-Thai")
        default:
            // en / de / fr / es / it / pt / vi / id / ms / tr など、Latin 系の言語は
            // そのまま Latin のままでよい（ステップ1の結果を返す）。
            return nil
        }
    }

    /// 端末言語が主に使うスクリプトを雑に判定する。判定は「音写を省略するか」にしか
    /// 使わないので、Latin 系は空のセットを返して素のまま流す（Latin 入力はステップ2を
    /// 素通りするため）。
    /// 日本語端末だけは CJK 漢字・ひらがな・カタカナの3種をまとめて判定する
    /// （漢字だけの名前もよく使われるため）。
    private func targetScripts(for code: String) -> Set<ScriptKind> {
        switch code {
        case "ja":
            return [.cjk, .hiragana, .katakana]
        case "ko":
            return [.hangul]
        case "ar":
            return [.arabic]
        case "ru", "uk", "be":
            return [.cyrillic]
        case "hi", "mr", "ne":
            return [.devanagari]
        case "he":
            return [.hebrew]
        case "el":
            return [.greek]
        case "th":
            return [.thai]
        default:
            // en/de/fr/... は素通り（ステップ1の Latin 表記をそのまま使う）。
            return []
        }
    }

    /// `text` のうち、`script` のいずれかの範囲に含まれる文字が1つでもあれば true。
    /// Swift の `Unicode.Scalar.Properties` には `script` が無いので、
    /// 必要な範囲だけを Unicode ブロックで直接判定する（依存を最小にするため）。
    private static func script(_ kind: ScriptKind, contains text: String) -> Bool {
        for scalar in text.unicodeScalars {
            if kind.range.contains(scalar.value) { return true }
        }
        return false
    }

    /// 文字列の主要スクリプトを判定する。空白・記号・数字など**どのスクリプトにも属さない
    /// 文字**（`ScriptKind` のどれにも該当しない）は飛ばし、最初に具体スクリプトに
    /// 当たったものを採用する。**どのスクリプトにも属さない場合**（絵文字・記号・数字のみの
    /// 文字列）は `nil` を返し、呼び出し側で絵文字のみ表示へフォールバックさせる。
    private func detectScript(of text: String) -> ScriptKind? {
        for scalar in text.unicodeScalars {
            // 空白・記号・数字・絵文字などは ScriptKind のどれにも当たらないので自然にスキップされる。
            for kind in ScriptKind.allCases where kind.range.contains(scalar.value) {
                return kind
            }
        }
        return nil
    }
}

/// Swift Foundation には `Unicode.Script` が露出していないため、必要なものだけを
/// 自前で範囲定義する（依存ライブラリを増やさないため）。
private enum ScriptKind: CaseIterable {
    /// CJK 統合漢字（U+4E00–U+9FFF）とその拡張 A〜F を含む。CJK のかな・記号を除く。
    case cjk
    case hiragana
    case katakana
    case hangul
    case arabic
    case cyrillic
    case devanagari
    case hebrew
    case greek
    case thai
    /// Latin（ASCII + Latin-1 Supplement + Latin Extended A/B）。欧米の名前はここ。
    case latin

    var range: ClosedRange<UInt32> {
        switch self {
        case .cjk:        return 0x4E00...0x9FFF
        case .hiragana:   return 0x3040...0x309F
        case .katakana:   return 0x30A0...0x30FF
        case .hangul:     return 0xAC00...0xD7AF
        case .arabic:     return 0x0600...0x06FF
        case .cyrillic:   return 0x0400...0x04FF
        case .devanagari: return 0x0900...0x097F
        case .hebrew:     return 0x0590...0x05FF
        case .greek:      return 0x0370...0x03FF
        case .thai:       return 0x0E00...0x0E7F
        case .latin:      return 0x0041...0x024F  // A–Z + a–z + 拡張
        }
    }
}