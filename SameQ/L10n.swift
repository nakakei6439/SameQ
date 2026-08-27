import Foundation

/// アプリ全体の UI 文言を、端末の言語に合わせて日本語／英語へ切り替える（F38 / スプリント15）。
///
/// 既存の `Translator` と同じく `Locale.preferredLanguages.first` を**起動時に1回だけ**
/// 読む（`Locale.current.language` は本アプリが Localizable.strings 等のリソースを
/// 持たないため、開発言語（既定 "en"）へ丸められる iOS の落とし穴を避けるため）。
///
/// 言語判定:
/// - `ja` で始まる → 日本語
/// - それ以外（en / fr / ko / ar / …）→ 英語（受け入れ条件「日本語でも英語でもない
///   端末言語（例：フランス語）では英語で表示され」）
///
/// `String(localized:)` 系 API を使わずに自前で日本語／英語の2セットを持つ理由:
/// - `Localizable.strings` + `Base.lproj/Localizable.strings` + `en.lproj/Localizable.strings`
///   だけで構成すると、開発地域を `ja` にしている都合上、フランス語端末が来たときに
///   Base（日本語）へフォールバックしてしまい、英語へ逃げられない。
/// - そこで「日本語／英語のどちらを使うか」を **言語判定で明示的に** 切り替え、
///   端末言語が日本語系でないものはすべて英語に寄せる。
/// - UI テストから `L10n.useEnglish` の値を観測できるので、テストでも挙動を確認できる。
enum L10n {
    /// 端末の `preferredLanguages` の先頭コード。起動時に1回だけ確定する。
    static let preferredLanguageCode: String = {
        let raw = Locale.preferredLanguages.first ?? "en"
        // `ja-JP` / `en-US` のように地域サフィックスが付いていても先頭2文字で判定する。
        return String(raw.prefix(2)).lowercased()
    }()

    /// 端末が日本語系かどうか。
    static let isJapanese: Bool = preferredLanguageCode == "ja"

    /// 端末が日本語系でないとき、英語UIを使う。
    static let useEnglish: Bool = !isJapanese

    // MARK: 共通

    enum Common {
        static let back: String = useEnglish ? "Back" : "戻る"
        static let close: String = useEnglish ? "Close" : "閉じる"
        static let cancel: String = useEnglish ? "Cancel" : "キャンセル"
        static let ok: String = "OK"
        static let retry: String = useEnglish ? "Try Again" : "もう一度試す"
        static let save: String = useEnglish ? "Save" : "保存"
        static let edit: String = useEnglish ? "Edit" : "編集"
        static let remove: String = useEnglish ? "Remove" : "解除"
        static let settings: String = useEnglish ? "Settings" : "設定"
        static let done: String = useEnglish ? "Done" : "完了"
        static let yes: String = useEnglish ? "Yes" : "はい"
        static let no: String = useEnglish ? "No" : "いいえ"
        static let next: String = useEnglish ? "Next" : "次へ"
        static let stop: String = useEnglish ? "Stop" : "やめる"
        static let submit: String = useEnglish ? "Submit" : "送信する"
        static let submitting: String = useEnglish ? "Submitting…" : "送信中…"
        static let processing: String = useEnglish ? "Processing…" : "処理中…"
        static let loading: String = useEnglish ? "Loading…" : "準備中…"
        static let loadingPrices: String = useEnglish ? "Loading price…" : "料金を読み込み中です…"
        static let readMore: String = useEnglish ? "…more" : "…続き"
    }

    // MARK: Onboarding

    enum Onboarding {
        static let conceptTitle: String = useEnglish
            ? "One question.\nOne answer."
            : "同じ問いに、\n答えるだけ。"

        static let conceptE1: String = useEnglish
            ? "Once a day, the whole world gets the same prompt. You never know when."
            : "1日1回、世界共通のお題が届きます。いつ届くかは分かりません。"
        static let conceptE2: String = useEnglish
            ? "Until you answer, you can't see anyone else's response."
            : "あなたが答えて初めて、世界の誰かの答えが見えるようになります。"
        static let conceptE3: String = useEnglish
            ? "No follows, no search, no ranking. Tap the heart, then move on."
            : "フォローも検索もランキングもありません。いいねを押して、次へ進むだけ。"
        static let conceptE4: String = useEnglish
            ? "Words from that day fade after a while."
            : "その日の言葉は、しばらくすると消えます。"

        static let termsTitle: String = useEnglish
            ? "Before you begin"
            : "はじめる前に"
        static let termsBody: String = useEnglish
            ? "Terms of Use"
            : "利用規約"
        static let privacyBody: String = useEnglish
            ? "Privacy Policy"
            : "プライバシーポリシー"
        static let agreeLabel: String = useEnglish
            ? "I agree to the Terms of Use and Privacy Policy"
            : "利用規約とプライバシーポリシーに同意します"

        static let emojiTitle: String = useEnglish
            ? "Pick one mark\nthat's yours"
            : "あなたの印を\n1つ選んでください"
        static let emojiDescription: String = useEnglish
            ? "Only this emoji is shown to people around the world. You can change it later."
            : "世界の誰かには、この絵文字だけが見えます。あとから変えられます。"

        static let nicknameTitle: String = useEnglish
            ? "Want a name\nto go with it?"
            : "呼び名を\n決めますか？"
        static let nicknameDescription: String = useEnglish
            ? "You can leave it blank. If you don't set one, only your emoji is shown."
            : "空のままでも進めます。未設定のときは絵文字だけが表示されます。"
        static let nicknamePlaceholder: String = useEnglish
            ? "Nickname (optional)"
            : "ニックネーム（任意）"
        static let nicknamePrivacyNote: String = useEnglish
            ? "Don't use your real name. The whole point of this app is that no one knows your country or language."
            : "本名は書かないでください。国や言語が分からないことが、このアプリの前提です。"

        static let notificationTitle: String = useEnglish
            ? "We'll let you know\nwhen the prompt arrives"
            : "お題が届いたら\nお知らせします"
        static let notificationDescription: String = useEnglish
            ? "Once a day, at a random time. You can change this later in Settings."
            : "通知は1日1回だけ。届く時刻は毎日変わります。あとで設定から変えられます。"
        static let notificationFootnote: String = useEnglish
            ? "Even with notifications off, you can still answer today's prompt by opening the app."
            : "通知を切っていても、アプリを開けばその日のお題に答えられます。"

        static let allowNotifications: String = useEnglish
            ? "Allow notifications"
            : "通知を許可する"
        static let later: String = useEnglish
            ? "Maybe later"
            : "あとで設定する"

        static let hintAgree: String = useEnglish
            ? "Agree to continue"
            : "同意すると次へ進めます"
        static let hintPickEmoji: String = useEnglish
            ? "Pick an emoji to continue"
            : "絵文字を1つ選んでください"

        static func emojiAccessibility(_ emoji: String) -> String {
            useEnglish ? "Emoji \(emoji)" : "絵文字 \(emoji)"
        }

        static let genericErrorTitle: String = useEnglish
            ? "Something went wrong"
            : "うまくいきませんでした"
    }

    // MARK: Today

    enum Today {
        static let promptLabel: String = useEnglish ? "TODAY'S PROMPT" : "今日のお題"
        static let composerPlaceholder: String = useEnglish
            ? "Try answering in your own words"
            : "あなたの言葉で答えてみてください"
        static let lockedTitle: String = useEnglish
            ? "The world is still hidden"
            : "世界の回答はまだ見られません"
        static let lockedBody: String = useEnglish
            ? "Once you answer, one stranger's words at a time will appear here."
            : "あなたが答えると、知らない誰かの言葉が1件ずつ見えるようになります。"
        static let submitButton: String = useEnglish ? "Post" : "投稿する"
        static let submittingButton: String = useEnglish ? "Posting…" : "送信中…"
        static let oneAnswerPerPrompt: String = useEnglish
            ? "You can answer each prompt only once."
            : "1つのお題に答えられるのは1回だけです"
        static let oneAnswerPerPromptPlus: String = useEnglish
            ? "You can answer each prompt only once (Plus long-form)."
            : "1つのお題に答えられるのは1回だけです（Plus 長文対応）"
        static let yourAnswer: String = useEnglish ? "YOUR ANSWER" : "あなたの回答"
        static let openTimeline: String = useEnglish
            ? "Read the world's answers"
            : "世界の回答を読む"
        static let preparingTimeline: String = useEnglish ? "Preparing…" : "準備中…"
        static func receivedLikesCount(_ count: Int) -> String {
            useEnglish
                ? "\(count) like\(count == 1 ? "" : "s")"
                : "\(count) 件のいいね"
        }
        static let plusHintTitle: String = useEnglish
            ? "Want to write more?"
            : "もっと書きたいときは"
        static let plusHintBody: String = useEnglish
            ? "Plus gives you long-form posts and decorations"
            : "Plus なら長文と装飾が使えます"

        static let plusEntryLabelActive: String = useEnglish ? "Plus active" : "Plus に登録済み"
        static let plusEntryLabelInactive: String = useEnglish ? "See Plus" : "Plus を見る"
    }

    // MARK: Timeline

    enum Timeline {
        static let title: String = useEnglish ? "THE WORLD'S ANSWERS" : "世界の回答"
        static let promptLabel: String = useEnglish ? "PROMPT" : "お題"
        static let swipeHint: String = useEnglish
            ? "Swipe to meet another stranger"
            : "スワイプすると、次の知らない誰かへ"
        static let like: String = useEnglish ? "Like" : "いいね"
        static let liked: String = useEnglish ? "Liked" : "いいね済み"
        static let likedStatus: String = useEnglish ? "You liked this" : "いいねしました"

        static let emptyTitle: String = useEnglish
            ? "No one has answered yet"
            : "まだ誰も答えていません"
        static let emptyBody: String = useEnglish
            ? "When someone in the world answers, their reply will appear here one by one."
            : "世界の誰かが答えると、ここに1件ずつ出てきます。"

        static let exhaustedTitle: String = useEnglish
            ? "No new answers right now"
            : "今は新しい回答がありません"
        static let exhaustedBody: String = useEnglish
            ? "You've read all the answers for this prompt. The words will fade after a while."
            : "このお題の回答はすべて読みました。読んだ言葉は、しばらくすると消えます。"

        static let moreAccessibility: String = useEnglish
            ? "Report or block this reply"
            : "この回答を通報またはブロック"
    }

    // MARK: Waiting

    enum Waiting {
        static let title: String = useEnglish ? "There's no prompt right now" : "いまはお題がありません"
        static let body: String = useEnglish
            ? "Hang tight until the next one arrives.\nWhen it does, you can answer from this screen."
            : "次のお題が届くまで、少し待ってください。\n始まったら、この画面から答えられます。"
        static let footnote: String = useEnglish
            ? "Words of the day fade by the end of the day."
            : "その日の言葉は、その日のうちに消えます。"
    }

    // MARK: Banned

    enum Banned {
        static let title: String = useEnglish
            ? "This account can no longer be used"
            : "このアカウントは利用できません"
        static let body: String = useEnglish
            ? "The operator has suspended this account. You can't access today's prompt or the timeline."
            : "運営がこのアカウントの利用を停止しました。今日のお題にも世界の回答にも入れません。"
    }

    // MARK: Safety sheet (Report / Block)

    enum Safety {
        static let menuHeader: String = useEnglish ? "About this reply" : "この回答について"
        static let menuHeaderDetail: String = useEnglish
            ? "Nothing you choose is shared with the other person."
            : "選んだ内容が相手に伝わることはありません。"

        static let reportAction: String = useEnglish ? "Report this reply" : "この回答を通報する"
        static let reportActionDetail: String = useEnglish
            ? "Pick a reason and send. The reply is hidden immediately."
            : "理由を選んで送ります。この回答はすぐに表示されなくなります。"
        static let blockAction: String = useEnglish ? "Block this person" : "この人をブロックする"
        static let blockActionDetail: String = useEnglish
            ? "You won't see any of their replies from now on."
            : "この人の回答が、これから1件も表示されなくなります。"

        static let blockConfirmAction: String = useEnglish
            ? "Block"
            : "ブロックする"

        static let reasonsTitle: String = useEnglish ? "Pick a reason" : "通報の理由を選んでください"
        static let reasonsDetail: String = useEnglish
            ? "Choose the one that fits best."
            : "当てはまるものを1つ選びます。"

        static let blockConfirmTitle: String = useEnglish
            ? "Block this person?"
            : "この人をブロックしますか？"
        static let blockConfirmDetail: String = useEnglish
            ? "You won't see any of their replies from now on.\nThey won't be told you blocked them."
            : "この人の回答は、これから1件も表示されなくなります。\nブロックしたことが相手に伝わることはありません。"

        static let reportDoneTitle: String = useEnglish
            ? "Report submitted"
            : "通報を受け付けました"
        static let reportDoneBody: String = useEnglish
            ? "This reply won't be shown anymore.\nThey won't be told you reported it."
            : "この回答はもう表示されません。\n通報したことが相手に伝わることはありません。"
        static let blockDoneTitle: String = useEnglish
            ? "This person is now blocked"
            : "この人をブロックしました"
        static let blockDoneBody: String = useEnglish
            ? "You won't see any of their replies from now on.\nThey won't be told you blocked them.\nYou can unblock anytime in Settings."
            : "この人の回答は、これから1件も表示されなくなります。\nブロックしたことが相手に伝わることはありません。\n設定からいつでも解除できます。"
    }

    enum ReportReason {
        static let politics: String = useEnglish
            ? "Incites political conflict"
            : "政治的な対立をあおる"
        static let religion: String = useEnglish
            ? "Incites religious conflict"
            : "宗教的な対立をあおる"
        static let discrimination: String = useEnglish
            ? "Discrimination or hate"
            : "差別・ヘイト"
        static let sexual: String = useEnglish
            ? "Sexual content"
            : "性的な内容"
        static let crime: String = useEnglish
            ? "Encourages crime"
            : "犯罪をすすめている"
        static let privacy: String = useEnglish
            ? "Contains personal information"
            : "個人情報が書かれている"
        static let other: String = useEnglish
            ? "Other unpleasant content"
            : "その他の不快な内容"
    }

    // MARK: Settings

    enum Settings {
        static let title: String = useEnglish ? "Settings" : "設定"

        static let profileSection: String = useEnglish ? "PROFILE" : "プロフィール"
        static let profilePlaceholder: String = useEnglish ? "No name set" : "名前のない人"
        static let profileEditHint: String = useEnglish ? "You can change this later" : "あとから変更できます"

        static let legalSection: String = useEnglish ? "LEGAL & PRIVACY" : "規約・プライバシー"
        static let legalTerms: String = useEnglish ? "Terms of Use" : "利用規約"
        static let legalPrivacy: String = useEnglish ? "Privacy Policy" : "プライバシーポリシー"

        static let notificationSection: String = useEnglish ? "NOTIFICATIONS" : "通知"
        static let notificationHeadlineOn: String = useEnglish
            ? "Daily prompts are on"
            : "お題のお知らせはオンです"
        static let notificationHeadlineOff: String = useEnglish
            ? "Daily prompts are off"
            : "お題のお知らせはオフです"
        static let notificationHeadlineUnknown: String = useEnglish
            ? "Daily prompts haven't been decided yet"
            : "お題のお知らせはまだ決まっていません"
        static let notificationDetailOn: String = useEnglish
            ? "Once a day, at a random time between 8:00 and 22:00, a new prompt arrives. The time changes every day."
            : "1日1回、8:00〜22:00 の間のランダムな時刻に、新しいお題をお届けします。時刻は毎日変わります。"
        static let notificationDetailOff: String = useEnglish
            ? "Turn notifications on to get a random daily prompt. You can enable them in iOS Settings › Notifications › SameQ."
            : "通知をオンにすると、1日1回ランダムな時刻に新しいお題が届きます。iOS の「設定 › 通知 › SameQ」からオンにできます。"
        static let notificationDetailUnknown: String = useEnglish
            ? "Turn notifications on to get a random daily prompt. You can change this anytime in iOS Settings › Notifications › SameQ."
            : "通知をオンにすると、1日1回ランダムな時刻に新しいお題が届きます。あとで設定 › 通知 › SameQ からいつでも変更できます。"
        static let notificationNextPrefix: String = useEnglish
            ? "Next prompt: "
            : "次のお知らせ: "

        static let plusSection: String = useEnglish ? "PLUS" : "Plus"
        static let plusHeadlineActive: String = useEnglish
            ? "You're on Plus"
            : "Plus に登録済みです"
        static let plusHeadlineInactive: String = useEnglish
            ? "Get more with Plus"
            : "Plus を使うと、もっと書ける"
        static let plusDetailActive: String = useEnglish
            ? "Long-form posts and decorations (stamps, bold, italic, balloons) are available. Manage your subscription in iOS Settings › Apple ID › Subscriptions."
            : "長文と装飾（スタンプ・太字・斜体・吹き出し）が使えます。購読の管理は iOS の「設定 › Apple ID › サブスクリプション」から行えます。"
        static let plusDetailInactive: String = useEnglish
            ? "Long-form posts (over 140 characters) and decorations like stamps, bold, italic, and balloons are available. Purchases go through the App Store and can be cancelled anytime."
            : "長文（140 文字超）と、スタンプ・太字・斜体・吹き出しの装飾が使えます。購入は App Store 経由で、解約はいつでもできます。"
        static let plusOpen: String = useEnglish ? "See Plus" : "Plus を見る"
        static let plusRestore: String = useEnglish ? "Restore Purchase" : "購入を復元"

        static let blockedSection: String = useEnglish ? "BLOCKED PEOPLE" : "ブロック中の人"
        static let blockedEmptyTitle: String = useEnglish
            ? "You haven't blocked anyone"
            : "ブロックしている人はいません"
        static let blockedEmptyBody: String = useEnglish
            ? "From the ⋯ on a timeline reply, you can hide someone's replies."
            : "タイムラインの ⋯ から、その人の回答を表示しないようにできます。"
        static let blockedUnblockHint: String = useEnglish
            ? "Unblocking will make their replies appear again."
            : "解除すると、その人の回答がまた表示されるようになります。"
        static let blockedNamePlaceholder: String = useEnglish ? "No name" : "名前のない人"

        static let accountSection: String = useEnglish ? "ACCOUNT" : "アカウント"
        static let accountDelete: String = useEnglish ? "Delete account" : "アカウントを削除"

        static let deleteDialogTitle: String = useEnglish
            ? "Delete your account?"
            : "アカウントを削除しますか？"
        static let deleteDialogConfirm: String = useEnglish ? "Delete" : "削除する"
        static let deleteDialogMessage: String = useEnglish
            ? "Your account, posts, likes, blocks, and reports will all be erased.\nThis can't be undone."
            : "アカウント・投稿・いいね・ブロック・通報の記録がすべて消えます。\nこの操作は取り消せません。"

        static let profileEditTitle: String = useEnglish ? "Edit Profile" : "プロフィール編集"
        static let profileEditEmojiTitle: String = useEnglish
            ? "Pick one mark\nthat's yours"
            : "あなたの印を\n1つ選んでください"
        static let profileEditNicknameLabel: String = useEnglish
            ? "Name (optional)"
            : "呼び名（任意）"
        static let profileEditNicknamePlaceholder: String = useEnglish
            ? "Nickname (optional)"
            : "ニックネーム（任意）"

        static let legalSheetTermsTitle: String = useEnglish ? "Terms of Use" : "利用規約"
        static let legalSheetPrivacyTitle: String = useEnglish ? "Privacy Policy" : "プライバシーポリシー"
    }

    // MARK: Plus

    enum Plus {
        static let navTitle: String = "Plus"

        static let heroTitle: String = useEnglish
            ? "More expression with Plus"
            : "Plus で広がる表現"
        static let heroBody: String = useEnglish
            ? "Write longer, in your own voice. Add a touch of style to your words."
            : "もっと長い文章で、もっとあなたらしく。長文と装飾で、言葉に少しだけ色を足せます。"

        static let benefitsTitle: String = useEnglish ? "WHAT YOU GET WITH PLUS" : "Plus でできること"
        static let benefitLongTitle: String = useEnglish ? "Long-form posts" : "長文の投稿"
        static let benefitLongBody: String = useEnglish
            ? "Go past 140 characters and write at your own pace."
            : "140文字を超えて、自分のペースで書き残せます。"
        static let benefitStampTitle: String = useEnglish ? "Plus-only stamps" : "Plus 限定スタンプ"
        static let benefitStampBody: String = useEnglish
            ? "Add a stamp to your post to give your words a personal flavor."
            : "本文に添える絵文字スタンプで、語りにひとつ癖を加えられます。"
        static let benefitDecorationTitle: String = useEnglish ? "Text decoration" : "文字装飾"
        static let benefitDecorationBody: String = useEnglish
            ? "Make parts of your post bold or italic to emphasize what matters."
            : "本文の一部を太字・斜体に。強調したい言葉を引き立てます。"
        static let benefitBalloonTitle: String = useEnglish ? "Balloon decoration" : "吹き出し装飾"
        static let benefitBalloonBody: String = useEnglish
            ? "Wrap a part of your post in a balloon, like a whisper or an aside."
            : "本文を吹き出しで囲んで、ささやきや独り言のような形を作れます。"

        static let priceTitle: String = useEnglish ? "PRICE" : "料金"
        static let priceMonthlySuffix: String = useEnglish ? "/ month" : "/ 月額"

        static let purchaseActive: String = useEnglish ? "Plus is active" : "Plus に登録済み"
        static let purchaseInactive: String = useEnglish ? "Subscribe to Plus" : "Plus に登録する"

        static let restoreTitle: String = useEnglish ? "RESTORE PURCHASE" : "購入の復元"
        static let restoreBody: String = useEnglish
            ? "If you delete and reinstall the app, you can bring your purchase back."
            : "アプリを削除してから入れ直したときも、購入した状態を引き継げます。"
        static let restoreActive: String = useEnglish ? "Restoring…" : "復元中…"
        static let restoreButton: String = useEnglish ? "Restore purchase" : "購入を復元"

        static let disclaimer1: String = useEnglish
            ? "Payment is handled by the App Store. You can cancel anytime from iOS Settings › Apple ID › Subscriptions."
            : "購入は App Store 経由で決済されます。期間中はいつでも設定 › Apple ID › サブスクリプション から解約できます。"
        static let disclaimer2: String = useEnglish
            ? "There's no paywall on reading. Even non-Plus users can read others' long-form posts with \"Read more\"."
            : "閲覧に課金制限はありません。Plus でない方も、他人の長文を「続きを読む」で全部読めます。"

        // Plus decoration picker
        static let pickerHeader: String = useEnglish ? "Plus decorations" : "Plus 装飾"
        static let pickerStampLabel: String = useEnglish ? "Stamps" : "スタンプ"
        static let pickerBoldLabel: String = useEnglish ? "Bold" : "太字"
        static let pickerItalicLabel: String = useEnglish ? "Italic" : "斜体"
        static let pickerBalloonLabel: String = useEnglish ? "Balloon" : "吹き出し"
        static let pickerBalloonValue: String = useEnglish ? "inner voice" : "心の声"
        static let pickerRemoveStamp: String = useEnglish ? "Remove stamp" : "スタンプを外す"
        static func pickerStampAccessibilityOn(_ emoji: String) -> String {
            useEnglish ? "Stamp \(emoji) selected" : "スタンプ\(emoji)を選択中"
        }
        static func pickerStampAccessibilityOff(_ emoji: String) -> String {
            useEnglish ? "Select stamp \(emoji)" : "スタンプ\(emoji)を選択"
        }
    }

    // MARK: Failure view

    enum Failure {
        static let title: String = useEnglish ? "Couldn't load" : "読み込めませんでした"
    }

    // MARK: Errors

    enum Errors {
        static let notSignedIn: String = useEnglish
            ? "We couldn't find your account. Please restart the app."
            : "アカウントが見つかりませんでした。アプリを起動し直してください。"
        static let emptyBody: String = useEnglish
            ? "You can't post a reply that's only blank space or line breaks."
            : "空白や改行だけの回答は投稿できません。"
        static func bodyTooLong(_ limit: Int) -> String {
            useEnglish
                ? "Replies can be at most \(limit) characters."
                : "回答は\(limit)文字までです。"
        }
        static let alreadyAnswered: String = useEnglish
            ? "You've already answered this prompt."
            : "このお題にはすでに回答しています。"
        static let promptNotActive: String = useEnglish
            ? "This prompt's time is up. Please wait for the next one."
            : "このお題の時間は終わりました。次のお題をお待ちください。"
        static let seedDataMissing: String = useEnglish
            ? "We couldn't load the prompt."
            : "お題を読み込めませんでした。"
        static func storageFailure(_ detail: String) -> String {
            useEnglish
                ? "Couldn't save (\(detail))."
                : "保存に失敗しました（\(detail)）。"
        }
        static let duplicateBody: String = useEnglish
            ? "This is identical to your previous post. Please try different wording."
            : "直前の自分の投稿と同じ内容です。別の言葉に変えて投稿してください。"
        static let meaninglessBody: String = useEnglish
            ? "A post made of the same character repeated isn't allowed."
            : "同じ文字を並べただけの投稿はできません。"
        static func rateLimited(_ actionName: String, _ retryAfter: Int) -> String {
            useEnglish
                ? "\(actionName) too fast. Please wait \(retryAfter)s and try again."
                : "\(actionName)が短時間に多すぎます。\(retryAfter)秒待ってからもう一度お試しください。"
        }
        static let rateLimitedActionLike: String = useEnglish ? "Likes" : "いいね"
        static let rateLimitedActionReport: String = useEnglish ? "Reports" : "通報"

        static let plusUserCancelled: String = useEnglish
            ? "Purchase cancelled."
            : "購入をキャンセルしました。"
        static let plusNetwork: String = useEnglish
            ? "There was a connection problem. Please check your signal and try again."
            : "通信に問題がありました。電波状況を確認してもう一度お試しください。"
        static let plusProductNotFound: String = useEnglish
            ? "We couldn't load the Plus product information."
            : "Plus の商品情報を読み込めませんでした。"
        static func plusOther(_ detail: String) -> String {
            useEnglish
                ? "Purchase failed (\(detail))."
                : "購入に失敗しました（\(detail)）。"
        }

        static let supabaseOffline: String = useEnglish
            ? "Can't connect. Please check your network."
            : "通信できません。ネットワーク接続を確認してください。"
        static let supabaseUnauthorized: String = useEnglish
            ? "Your session expired. Please try again."
            : "セッションが切れました。もう一度やり直してください。"
        static let supabaseNotFound: String = useEnglish
            ? "We couldn't find what you were looking for."
            : "該当のデータが見つかりませんでした。"
        static let supabaseDuplicate: String = useEnglish
            ? "This data already exists."
            : "すでに同じデータが存在します。"
        static func supabaseForbidden(_ detail: String) -> String {
            useEnglish
                ? "This action isn't allowed (\(detail))."
                : "この操作は許可されていません（\(detail)）。"
        }
        static func supabaseServer(_ message: String) -> String {
            useEnglish
                ? "The server returned an error (\(message))."
                : "サーバーでエラーが発生しました（\(message)）。"
        }
        static func supabaseMalformed(_ detail: String) -> String {
            useEnglish
                ? "Couldn't read the server's response (\(detail))."
                : "サーバーからの応答を解釈できませんでした（\(detail)）。"
        }
        static func supabaseTransport(_ detail: String) -> String {
            useEnglish
                ? "Connection error (\(detail))."
                : "通信エラー（\(detail)）。"
        }
        static let supabaseFunctionMissing: String = useEnglish
            ? "Some server features haven't been activated yet. If restarting the app doesn't help, please contact support."
            : "サーバー機能の一部が未適用です。アプリを再起動しても直らない場合はサポートまでお知らせください。"
    }
}
