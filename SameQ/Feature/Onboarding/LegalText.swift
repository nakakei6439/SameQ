import Foundation

/// 利用規約とプライバシーポリシーの本文（F52）。
///
/// 内容は実装済みの挙動（匿名認証・端末内翻訳・投稿の寿命・安全ログ30日保持等）に
/// 基づく。運営者名・問い合わせ先・準拠法・裁判管轄は、Web版（`nakakei6439.github.io/sameq/`）
/// と同一の内容で確定済み。
///
/// **日英の2言語を持つ**（置いた前提19。スプリント20で改訂）。
/// 規約への同意は「読める規約」に対してしか成立しない。英語端末の利用者が
/// 日本語の規約しか読めない状態では、同意を求めている意味がなく、規約に書いた
/// 禁止事項も相手に届かない。法的な正文は日本語で、英語版はその翻訳。
///
/// **ゼロトレランス条項は第2条に置く**。オンボーディングの規約は高さ150ptの
/// スクロールボックス（`OnboardingView.legalCard`）に収まるので、条文の奥に
/// 置くと読まれない。同意チェックのすぐ上にも `L10n.Onboarding.zeroToleranceSummary`
/// で要約を常時表示している。
///
/// **Web版（`nakakei6439.github.io/sameq/terms.html` / `privacy.html`）と条番号・
/// 内容を一致させること。** アプリ側のこのファイルを正とし、Web はここから写す。
enum LegalText {
    /// 規約の版（F53）。**本文を変えたら必ずこの値も変える。**
    /// `PersistedState.termsAcceptance.version` がこれと違う利用者には、
    /// 起動時に再同意を求める（置いた前提42）。
    static let version = "2026-09-09"

    /// 端末言語に応じた利用規約。
    static var terms: String { L10n.useEnglish ? termsEN : termsJA }
    /// 端末言語に応じたプライバシーポリシー。
    static var privacy: String { L10n.useEnglish ? privacyEN : privacyJA }

    // MARK: 利用規約（日本語・正文）

    static let termsJA = """
    第1条（適用）
    本規約は、SameQ（以下「本サービス」）の利用条件を定めるものです。利用者は本規約に同意のうえ本サービスを利用するものとします。

    第2条（不適切な投稿と迷惑行為に対する方針）
    運営は、第6条に定める禁止事項に該当する投稿、および他の利用者に対する迷惑行為を、一切許容しません。
    運営は、利用者からの通報および自動的な検知に基づき、当該投稿を削除または非表示にし、その投稿を行った利用者のアカウントを予告なく停止（BAN）します。停止されたアカウントとその投稿は復元されません。

    第3条（アカウント）
    本サービスは匿名で利用できます。メールアドレス・電話番号その他の個人を特定する情報の入力は求めません。1台の端末につき1つのアカウントを、内部IDで識別します。

    第4条（対象年齢）
    本サービスは18歳以上の方を対象としています。

    第5条（投稿）
    利用者は、1つのお題につき1回だけ回答を投稿できます。投稿は表示期限（原則24時間、最長36時間）の経過後、他の利用者から見えなくなります。

    第6条（禁止事項）
    利用者は、本サービスの利用にあたり、以下の行為をしてはなりません。
    (1) 差別的表現、他者への誹謗中傷・攻撃
    (2) 性的な内容
    (3) 犯罪を助長し、または勧誘する内容
    (4) 個人情報（自他を問わない）の記載
    (5) 政治的・宗教的な対立を煽る内容
    (6) その他、運営が不適切と判断する内容

    第7条（通報と運営の対応）
    1. 利用者は、他の利用者の回答を、その回答の「⋯」から通報できます。また、設定画面の「お問い合わせ」から運営に直接連絡できます。
    2. 運営は、受け付けた通報を24時間以内に確認し、必要と判断した場合は当該投稿を削除し、その投稿を行った利用者のアカウントを停止します。
    3. 複数の利用者から通報を受けた投稿は、運営の確認を待たずに自動的に非表示となります。

    第8条（ブロックと自分の投稿の削除）
    1. 利用者は、他の利用者をブロックできます。ブロックした相手の回答は、以後表示されません。ブロックは設定画面から解除できます。
    2. 利用者は、自分の回答をいつでも削除できます。削除した回答は、直ちにすべての利用者の画面から見えなくなります。ただし、削除したあと、同じお題に改めて回答することはできません。

    第9条（アプリ内課金）
    SameQ Plus は自動更新のサブスクリプションです。料金と期間はアプリ内の購入画面に表示されます。期間終了の24時間前までに解約しない限り自動的に更新され、更新料金は期間終了前の24時間以内に請求されます。購入の管理および解約は、端末の「設定」→ Apple Account →「サブスクリプション」から行えます。無料トライアル期間中に解約した場合、料金は発生しません。未使用期間の払い戻しは行いません。

    第10条（利用者による退会）
    利用者は、設定画面からいつでも自分のアカウントと投稿を削除できます。削除後、そのアカウントは復元できません。

    第11条（免責）
    本サービスは、利用者間で生じた紛争について、故意または重過失がある場合を除き責任を負いません。本サービスは現状有姿で提供され、運営はその完全性・正確性・有用性・特定目的への適合性について、明示または黙示を問わず保証しません。

    第12条（規約の変更）
    運営は、必要と判断した場合に本規約を変更できます。重要な変更がある場合は、アプリ内で周知し、改めて同意を求めます。

    第13条（準拠法・管轄）
    本規約は日本法に準拠し、本サービスに関して紛争が生じた場合は、東京地方裁判所を第一審の専属的合意管轄裁判所とします。

    第14条（お問い合わせ）
    本サービスに関するお問い合わせは、nakakei6439@gmail.com までご連絡ください。

    運営者：Keita Nakagawa
    最終更新日：2026年9月9日
    """

    // MARK: Terms of Use (English translation)

    static let termsEN = """
    Note: The Japanese version of these Terms is the authoritative text. This English version is a translation provided for convenience. In case of any discrepancy, the Japanese version prevails.

    Article 1 (Application)
    These Terms of Use ("Terms") set out the conditions for using SameQ (the "Service"). By using the Service, you agree to these Terms.

    Article 2 (Zero Tolerance for Objectionable Content and Abusive Users)
    We have zero tolerance for objectionable content and for abusive users. Content that falls under the prohibited conduct in Article 6, and abusive behaviour toward other users, are not tolerated in any form.
    Based on user reports and automated detection, we will remove or hide such content and will suspend (ban) the account that posted it, without prior notice. Suspended accounts and their posts are not restored.

    Article 3 (Account)
    The Service can be used anonymously. We do not ask for an email address, phone number, or any other personally identifying information. One account per device is identified by an internal ID.

    Article 4 (Age Requirement)
    The Service is intended for users aged 18 and over.

    Article 5 (Posts)
    You may submit one answer per prompt. An answer stops being visible to other users after its display period ends (24 hours in principle, up to 36 hours).

    Article 6 (Prohibited Conduct)
    When using the Service, you must not:
    (1) Post discriminatory expression, or defamation of or attacks on others
    (2) Post sexual content
    (3) Post content that promotes or solicits crime
    (4) Post personal information, whether your own or someone else's
    (5) Post content that incites political or religious conflict
    (6) Post anything else we judge to be inappropriate

    Article 7 (Reporting and Our Response)
    1. You can report another user's answer from the "..." menu on that answer. You can also contact us directly from Settings > Contact us.
    2. We review every report we receive within 24 hours and, where we judge it warranted, we remove the offending content and suspend the account of the user who provided it.
    3. An answer reported by several users is hidden automatically, without waiting for our review.

    Article 8 (Blocking and Deleting Your Own Post)
    1. You can block another user. You will no longer see answers from a user you have blocked. Blocks can be lifted in Settings.
    2. You can delete your own answer at any time. A deleted answer immediately stops being visible to every user. Note that after deleting it you cannot answer the same prompt again.

    Article 9 (In-App Purchases)
    SameQ Plus is an auto-renewing subscription. The price and the billing period are shown on the purchase screen in the app. It renews automatically unless you cancel at least 24 hours before the end of the current period, and your account is charged within 24 hours prior to the end of the current period. You can manage or cancel your subscription in Settings > Apple Account > Subscriptions on your device. If you cancel during a free trial, you are not charged. No refund is provided for the unused portion of a term.

    Article 10 (Deleting Your Account)
    You can delete your account and your posts at any time from the Settings screen. Once deleted, the account cannot be restored.

    Article 11 (Disclaimer)
    We accept no liability for disputes between users, except in cases of our willful misconduct or gross negligence. The Service is provided "as is," and we make no warranties, express or implied, as to its completeness, accuracy, usefulness, or fitness for a particular purpose.

    Article 12 (Changes to these Terms)
    We may change these Terms when we judge it necessary. If a change is significant, we will announce it in the app and ask you to agree again.

    Article 13 (Governing Law and Jurisdiction)
    These Terms are governed by the laws of Japan. Any dispute relating to the Service shall be subject to the exclusive jurisdiction of the Tokyo District Court as the court of first instance.

    Article 14 (Contact)
    For any question about the Service, please contact nakakei6439@gmail.com.

    Operator: Keita Nakagawa
    Last updated: September 9, 2026
    """

    // MARK: プライバシーポリシー（日本語・正文）

    static let privacyJA = """
    SameQ（以下「本サービス」）における個人情報・利用者情報の取り扱いについて、以下のとおり定めます。

    1. 取得する情報
    匿名の内部ID、選択された絵文字、任意のニックネーム、投稿本文、いいね・既読・通報・ブロックの記録を取得します。氏名・メールアドレス・電話番号・位置情報の入力は求めず、取得しません。

    2. 翻訳について
    投稿本文とニックネームの翻訳・言語表示変換は、Apple の端末内翻訳機能（Translation Framework）を用いて端末上で行います。翻訳のために本文を外部サーバーへ送信することはありません。

    3. 不適切な投稿の検知について
    投稿本文とニックネームは、禁止された表現を含むかどうかを、端末内と本サービスのサーバー上で照合します。この照合は本サービス内で完結し、判定のために本文を外部の事業者へ送信することはありません。

    4. 利用目的
    取得した情報は、本サービスの提供（投稿の表示、既読管理、通報・ブロックの反映）および不適切な投稿への対応のためにのみ利用します。

    5. 保存期間
    投稿は表示期限の経過後、他の利用者からは見えなくなりますが、不適切な投稿への対応など安全対策のため、目安30日間はサーバー側にログとして保持し、期間経過後に自動的に削除します。自分で削除した投稿も、同じ目的と期間で保持されます。

    6. アカウント削除
    設定画面からアカウント削除を行うと、当該利用者の投稿は他の利用者のタイムラインに表示されなくなります。安全ログとしての保持期間（上記5）を除き、以後の新たな取り扱いは行いません。

    7. 課金情報について
    Plus プランの購入は Apple の StoreKit を通じて行われ、クレジットカード情報等の決済情報自体を本サービスが取得することはありません。

    8. 第三者提供
    法令に基づく場合を除き、取得した情報を本人の同意なく第三者へ提供しません。

    9. お問い合わせ
    本ポリシーに関するお問い合わせは、nakakei6439@gmail.com までご連絡ください。

    運営者：Keita Nakagawa
    最終更新日：2026年9月9日
    """

    // MARK: Privacy Policy (English translation)

    static let privacyEN = """
    Note: The Japanese version of this Privacy Policy is the authoritative text. This English version is a translation provided for convenience.

    This policy describes how SameQ (the "Service") handles personal and user information.

    1. Information we collect
    We collect an anonymous internal ID, the emoji you choose, an optional nickname, the text of your answers, and records of your likes, reads, reports and blocks. We do not ask for and do not collect your name, email address, phone number or location.

    2. Translation
    Translation and script conversion of answers and nicknames are performed on your device using Apple's Translation framework. We never send the text of a post to any external server for translation.

    3. Detection of objectionable content
    The text of answers and nicknames is checked against a list of prohibited expressions, both on your device and on our own server. This check is performed entirely within the Service; we never send the text to any third party for evaluation.

    4. Purpose of use
    We use the information we collect only to provide the Service (showing answers, tracking what you have read, applying your reports and blocks) and to act on objectionable content.

    5. Retention
    After an answer's display period ends it is no longer visible to other users. For safety purposes, including acting on objectionable content, we keep it as a server-side log for approximately 30 days and then delete it automatically. An answer you delete yourself is retained for the same purpose and period.

    6. Deleting your account
    When you delete your account from the Settings screen, your answers stop appearing in other users' timelines. Apart from the safety-log retention described in section 5, we make no further use of your information.

    7. Payment information
    Purchases of the Plus plan are handled through Apple's StoreKit. We never receive or store payment details such as credit card numbers.

    8. Disclosure to third parties
    We do not provide the information we collect to third parties without your consent, except where required by law.

    9. Contact
    For any question about this policy, please contact nakakei6439@gmail.com.

    Operator: Keita Nakagawa
    Last updated: September 9, 2026
    """
}
