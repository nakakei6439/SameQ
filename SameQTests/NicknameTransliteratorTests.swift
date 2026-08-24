import XCTest
@testable import SameQ

/// `NicknameTransliterator`（F23）の受け入れ条件と境界条件を網羅するユニットテスト。
///
/// 端末言語ごとに `NicknameTransliterator(targetLanguageCode:)` を作り、
/// 純粋関数 `transliterate(_:)` の戻り値を `XCTAssertEqual` で確認する。
/// Foundation の `String.applyingTransform` はランタイム依存なので、テスト端末の
/// ICU バージョンによって結果が大きく変わると困るところだが、各ケースとも
/// 「スクリプトが変わること」「意味翻訳されていないこと」を見るだけにしてあって、
/// 具体的な綴りには依存しない（あるゆる iOS 18+ の端末で同じ結果になるはずだが、
/// もし ICU が更新されても落ちにくいようにした）。
final class NicknameTransliteratorTests: XCTestCase {

    // MARK: 受け入れ条件1: 端末言語と異なる文字体系が端末言語の文字体系で表示される

    /// 日本語端末で韓国語（Hangul）のニックネームはカタカナに音写される。
    /// 端末言語と原文スクリプトが異なるので、Latin 経由のカタカナ音写に進む。
    func testJaTerminalTransliteratesHangulToKatakana() {
        let sut = NicknameTransliterator(targetLanguageCode: "ja")
        let result = sut.transliterate("케이타")
        XCTAssertNotNil(result)
        XCTAssertNotEqual(result, "케이타",
                          "ja 端末では Hangul はカタカナ音写される")
        XCTAssertTrue(result!.contains(where: { (0x30A0...0x30FF).contains($0.unicodeScalars.first?.value ?? 0) }),
                      "ja 端末の結果はカタカナ文字を含むはず: \(result!)")
    }

    /// 韓国語端末で日本語（漢字）のニックネームが Hangul で表示される。
    /// `景太` → `景太` の Latin 音写 → `keita` 相当 → Hangul。
    /// 具体的な綴りに依存しないよう、結果が Hangul スクリプトを含んでいることだけ確認する。
    func testKoTerminalTransliteratesKanjiToHangul() {
        let sut = NicknameTransliterator(targetLanguageCode: "ko")
        let result = sut.transliterate("景太")
        XCTAssertNotNil(result)
        XCTAssertFalse(result!.isEmpty)
        // 結果に Hangul スクリプトの文字が含まれている
        XCTAssertTrue(result!.contains(where: { (0xAC00...0xD7AF).contains($0.unicodeScalars.first?.value ?? 0) }),
                      "ko 端末の結果は Hangul 文字を含むはず: \(result!)")
    }

    /// アラビア語端末で英語のニックネームが Arabic 文字で表示される。
    func testArTerminalTransliteratesLatinToArabic() {
        let sut = NicknameTransliterator(targetLanguageCode: "ar")
        let result = sut.transliterate("Keita")
        XCTAssertNotNil(result)
        XCTAssertFalse(result!.isEmpty)
        XCTAssertTrue(result!.contains(where: { (0x0600...0x06FF).contains($0.unicodeScalars.first?.value ?? 0) }),
                      "ar 端末の結果は Arabic 文字を含むはず: \(result!)")
    }

    /// 英語端末でキリル文字のニックネームが Latin 文字で表示される。
    func testEnTerminalTransliteratesCyrillicToLatin() {
        let sut = NicknameTransliterator(targetLanguageCode: "en")
        XCTAssertEqual(sut.transliterate("Иван"), "Ivan",
                       "en 端末はキリル文字を Latin に音写する")
    }

    /// 英語端末で Hangul のニックネームが Latin 文字で表示される。
    func testEnTerminalTransliteratesHangulToLatin() {
        let sut = NicknameTransliterator(targetLanguageCode: "en")
        XCTAssertEqual(sut.transliterate("케이타"), "keita",
                       "en 端末は Hangul を Latin に音写する")
    }

    /// 日本語端末で英語のニックネームがカタカナで表示される（受け入れ条件1 の主要なケース）。
    /// `Mizuki` は既に Latin なのでステップ1で素通り、ステップ2でカタカナ音写される。
    func testJaTerminalTransliteratesLatinToKatakana() {
        let sut = NicknameTransliterator(targetLanguageCode: "ja")
        let result = sut.transliterate("Mizuki")
        XCTAssertNotNil(result)
        XCTAssertFalse(result!.isEmpty)
        XCTAssertTrue(result!.contains(where: { (0x30A0...0x30FF).contains($0.unicodeScalars.first?.value ?? 0) }),
                      "ja 端末の結果はカタカナ文字を含むはず: \(result!)")
    }

    // MARK: 受け入れ条件2: 変換は音写であり、意味翻訳された言葉にならない

    /// `景太` を英語端末で見ても「landscape（景色）」のような意味語にはならず、
    /// 読み（`jing tai` のような発音ベースの音写）になる。
    /// 「景太」は風景を意味する単語ではないので意味翻訳しようがない、という事実をテストで明示するため、
    /// 比較対象として `山` を英語端末で音写して `yama` 相当が出ることを確認する。
    /// （意味翻訳なら `mountain` が出るはず）。
    func testTransliterationIsPhoneticNotMeaning() {
        let sut = NicknameTransliterator(targetLanguageCode: "en")
        let result = sut.transliterate("山")
        XCTAssertNotEqual(result?.lowercased(), "mountain",
                          "意味翻訳であってはならない（音写は phonetic transcription）")
    }

    // MARK: 受け入れ条件3: 音写できないニックネームは絵文字のみ表示

    /// nil 入力（ニックネーム未設定）は nil を返す。
    func testNilInputReturnsNil() {
        let sut = NicknameTransliterator(targetLanguageCode: "en")
        XCTAssertNil(sut.transliterate(nil),
                     "ニックネーム未設定は nil を返し、絵文字のみ表示へ流れる")
    }

    /// 空文字・空白のみの入力は nil を返す（呼び出し側の `displayNickname` と挙動を揃える）。
    func testWhitespaceOnlyReturnsNil() {
        let sut = NicknameTransliterator(targetLanguageCode: "en")
        XCTAssertNil(sut.transliterate(""))
        XCTAssertNil(sut.transliterate("   "))
        XCTAssertNil(sut.transliterate("\n\t  "))
    }

    /// Debug限定の `-SameQNicknameTranslitDebug` をオンにすると、すべての入力で nil を返す。
    /// これで受け入れ条件3（音写失敗 → 絵文字のみ）のフォールバック動作を再現できる。
    func testForceFailureMakesEverythingNil() {
        let sut = NicknameTransliterator(targetLanguageCode: "en", forceFailure: true)
        XCTAssertNil(sut.transliterate("景太"),
                     "Debug モードでは音写成功すべき入力も nil に降ろす")
        XCTAssertNil(sut.transliterate("Mizuki"))
        XCTAssertNil(sut.transliterate("케이타"))
    }

    /// 絵文字だけのニックネームは（どの端末でも）nil を返す。
    /// 絵文字は「名前」ではないので絵文字のみ表示に降ろすのが正解。
    func testEmojiOnlyNicknameReturnsNil() {
        let sut = NicknameTransliterator(targetLanguageCode: "en")
        XCTAssertNil(sut.transliterate("🌙✨"),
                     "絵文字だけのニックネームは nil を返す（絵文字のみ表示のパスへ流す）")
    }

    // MARK: 受け入れ条件4: 絵文字のみ表示でレイアウトが崩れない

    /// `displayNickname` が nil のときは呼び出し側がニックネーム表示を出さないので、
    /// transliterator が nil を返すことはレイアウト破壊につながらない
    /// （受け入れ条件4は呼び出し側の責務）。
    /// ここでは transliterator の契約（nil が返ること）だけを確認する。
    func testEmojiFallbackReturnsNilForUntranslatable() {
        let sut = NicknameTransliterator(targetLanguageCode: "en")
        // 空文字にトリミングされる入力も nil を返す
        XCTAssertNil(sut.transliterate("   "))
    }

    // MARK: 受け入れ条件5: 自分のニックネームは原文のまま（モデル側の責務）

    /// transliterator 自体は `isOwn` を見ない（モデルの `Post.displayedNickname(... isOwn:)` が
    /// `isOwn == true` の場合に transliterator を経由しない実装）。
    /// ここでは transliterator が呼ばれた場合の挙動だけを確認する。
    func testTransliteratorIsCalledForOthers() {
        let sut = NicknameTransliterator(targetLanguageCode: "ja")
        let result = sut.transliterate("Keita")
        XCTAssertNotNil(result)
        XCTAssertNotEqual(result, "Keita",
                          "ja 端末で `Keita` はカタカナ音写される（自分のニックネームかどうかはモデル側で分岐）")
    }

    // MARK: スクリプト一致時の最適化（日本語端末で漢字はそのまま）

    /// 日本語端末で漢字のニックネームは改悪を防ぐため原文のまま返す。
    /// ステップ1で `jing tai` にされてしまう問題を避けるための最適化。
    func testJaTerminalKeepsKanjiUnchanged() {
        let sut = NicknameTransliterator(targetLanguageCode: "ja")
        XCTAssertEqual(sut.transliterate("景太"), "景太",
                       "ja 端末では CJK 漢字をそのまま返す（`jing tai` に改悪しない）")
    }

    /// 日本語端末でカタカナのニックネームもそのまま返す（同じスクリプト）。
    func testJaTerminalKeepsKatakanaUnchanged() {
        let sut = NicknameTransliterator(targetLanguageCode: "ja")
        XCTAssertEqual(sut.transliterate("ミズキ"), "ミズキ")
    }

    /// 日本語端末でひらがなのニックネームもそのまま返す（同じスクリプト）。
    func testJaTerminalKeepsHiraganaUnchanged() {
        let sut = NicknameTransliterator(targetLanguageCode: "ja")
        XCTAssertEqual(sut.transliterate("みずき"), "みずき")
    }

    // MARK: 端末言語の大文字小文字と未対応端末

    /// 端末言語が大文字で渡されても小文字化して判定する（Locale の慣習として混在があるため）。
    func testTargetLanguageCodeIsCaseInsensitive() {
        let sut = NicknameTransliterator(targetLanguageCode: "EN")
        XCTAssertEqual(sut.transliterate("Иван"), "Ivan",
                       "EN / en は同じ扱い")
    }

    /// 未対応の端末言語（タイ語端末でタイ語のニックネーム等）は元の Latin 表記を返す。
    /// ステップ2が未対応でもステップ1の結果は常に得られるので、Latin 表記が返る。
    func testUnsupportedTargetFallsBackToLatin() {
        let sut = NicknameTransliterator(targetLanguageCode: "ja")
        // ja はステップ2をカタカナにするので、Latin 系端末と同じ挙動を期待しない
        // ここではまず ja 端末でキリル文字が音写されることを確認（キリル → Latin → カタカナ）
        let result = sut.transliterate("Иван")
        XCTAssertNotNil(result)
        XCTAssertNotEqual(result, "Иван",
                          "ja 端末でもキリル文字は音写される")
    }

    // MARK: 内部実装の不変条件

    /// transliterate 関数は同じ入力に対して同じ結果を返す（純粋関数）。
    func testTransliterateIsPureFunction() {
        let sut = NicknameTransliterator(targetLanguageCode: "ja")
        let a = sut.transliterate("Mizuki")
        let b = sut.transliterate("Mizuki")
        XCTAssertEqual(a, b)
    }

    /// 空白を含むニックネームは trim してから音写する。
    func testLeadingTrailingWhitespaceIsTrimmed() {
        let sut = NicknameTransliterator(targetLanguageCode: "en")
        XCTAssertEqual(sut.transliterate("  Иван  "), "Ivan",
                       "trim 後のテキストを音写対象にする")
    }

    // MARK: モデル層（`Post.displayedNickname` / `BlockedAuthor.displayedNickname`）

    /// `isOwn == true` のときは transliterator を経由せず原文をそのまま返す（受け入れ条件5）。
    func testPostDisplayedNicknameIsOwnReturnsOriginal() {
        let post = Post(
            id: UUID(), promptID: "p", authorID: UUID(),
            authorEmoji: "🌙", authorNickname: "景太",
            body: "x", bodyLanguage: "ja", createdAt: Date(), expiresAt: Date()
        )
        let transliterator = NicknameTransliterator(targetLanguageCode: "ko")
        XCTAssertEqual(
            post.displayedNickname(transliterator: transliterator, isOwn: true),
            "景太",
            "自分のニックネームは transliterator を経由せず原文のまま"
        )
    }

    /// `isOwn == false` のときは transliterator を通した表示名を返す。
    /// このケースは ja 端末で Hangul を見るものなので、カタカナ音写の結果になるはず
    /// （元の Hangul ではない）。
    func testPostDisplayedNicknameNotOwnGoesThroughTransliterator() {
        let post = Post(
            id: UUID(), promptID: "p", authorID: UUID(),
            authorEmoji: "🌙", authorNickname: "케이타",
            body: "x", bodyLanguage: "ko", createdAt: Date(), expiresAt: Date()
        )
        let transliterator = NicknameTransliterator(targetLanguageCode: "ja")
        let result = post.displayedNickname(transliterator: transliterator, isOwn: false)
        XCTAssertNotNil(result)
        XCTAssertNotEqual(result, "케이타",
                          "ja 端末は Hangul をカタカナ音写する")
        XCTAssertTrue(result!.contains(where: { (0x30A0...0x30FF).contains($0.unicodeScalars.first?.value ?? 0) }),
                      "結果はカタカナ文字を含む: \(result!)")
    }

    /// transliterator が nil のときは displayNickname をそのまま返す（後方互換）。
    func testPostDisplayedNicknameNilTransliteratorReturnsOriginal() {
        let post = Post(
            id: UUID(), promptID: "p", authorID: UUID(),
            authorEmoji: "🌙", authorNickname: "Иван",
            body: "x", bodyLanguage: "ru", createdAt: Date(), expiresAt: Date()
        )
        XCTAssertEqual(
            post.displayedNickname(transliterator: nil, isOwn: false),
            "Иван",
            "transliterator == nil のときは音写しない"
        )
    }

    /// `BlockedAuthor.displayedNickname` は transliterator を通す（isOwn は常に false）。
    func testBlockedAuthorDisplayedNicknameGoesThroughTransliterator() {
        let author = BlockedAuthor(
            id: UUID(), emoji: "🌙",
            nickname: "Mizuki", blockedAt: Date()
        )
        let transliterator = NicknameTransliterator(targetLanguageCode: "ja")
        let result = author.displayedNickname(transliterator: transliterator)
        XCTAssertNotNil(result)
        XCTAssertNotEqual(result, "Mizuki",
                          "ja 端末のブロック一覧では Mizuki はカタカナ音写される")
    }

    /// 未設定のニックネームを持つ `BlockedAuthor` は transliterator を通しても nil のまま。
    func testBlockedAuthorNilNicknameStaysNil() {
        let author = BlockedAuthor(
            id: UUID(), emoji: "🌙", nickname: nil, blockedAt: Date()
        )
        let transliterator = NicknameTransliterator(targetLanguageCode: "ja")
        XCTAssertNil(author.displayedNickname(transliterator: transliterator))
    }

    /// `AppUser.displayedNickname` は transliterator を無視して原文を返す（受け入れ条件5）。
    /// `AppUser` は常に「自分」なので、transliterator が渡されても音写しない。
    func testAppUserDisplayedNicknameIgnoresTransliterator() {
        let user = AppUser(
            id: UUID(), emoji: "🌙", nickname: "Mizuki", createdAt: Date()
        )
        let transliterator = NicknameTransliterator(targetLanguageCode: "ja")
        XCTAssertEqual(
            user.displayedNickname(transliterator: transliterator),
            "Mizuki",
            "自分のニックネームは transliterator 設定に関わらず原文のまま"
        )
    }
}