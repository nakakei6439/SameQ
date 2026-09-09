# App Review 対応メモ（Guideline 1.2 UGC / 3.1.2 サブスク）

対象: **1.0.3 (8)** — 2026-09-09 の 1.0.2 (7) リジェクト（Submission ID
`8e7b3e06-9aa8-4eee-adc9-3756a7f69468`）への再提出。

過去2回の返信文はセッションのスクラッチパッドに書いて消えてしまったので、
今回はリポジトリに残す。文面は 1.0.3 (8) の実装に合わせて確定済み。

---

## App Review Notes（審査メモ欄に貼る英文）

```
== What SameQ is ==

SameQ has no chat, no direct messages, no following, no search, no
ranking and no image uploads. Once a day everyone receives the same
prompt. A user writes one short text answer, and only then can they
read other users' answers, one at a time. Answers disappear after
24-36 hours. The only content a user can create is short text, an
emoji avatar and an optional nickname.

== How to reach the Report / Block controls ==

Please follow these steps in order. Answers from other users are only
unlocked after you answer yourself - this is the core rule of the app,
not a bug.

  1. Complete onboarding (accept the terms, pick an emoji).
  2. On the Today screen, type any text and tap the submit button.
  3. Tap "Read answers from the world".
  4. Tap the "..." button at the top of the answer.
     Report and Block are both there.

== Guideline 1.2 - the eight precautions ==

1. Age rating
   Updated to 18+.

2. Agreement to terms (EULA), with no tolerance for objectionable
   content or abusive users
   Onboarding step 2 shows the Terms of Use and the Privacy Policy and
   requires an explicit checkbox before an account is created. The
   terms now state, near the top, that we do not tolerate objectionable
   content or abuse of other users, that reports are reviewed within 24
   hours, that violating posts are removed and that the accounts
   responsible are suspended. A one-line summary of that statement is
   shown directly above the checkbox. Both documents are available in
   English and Japanese, and can be reopened at any time from
   Menu > Settings.

3. Filtering objectionable content
   Every answer and every nickname is checked against a blocklist
   before it is stored - on the device and again on the server, so a
   modified client cannot bypass it. Blocked submissions are rejected
   with an explanation and never reach the feed. To see it in action,
   type any common profanity into the answer field and tap submit.

4. Flagging objectionable content
   The "..." button on any answer > Report. Choose a reason and submit.
   The answer disappears from your feed immediately and never returns.

5. Blocking abusive users
   The same "..." button > Block. That user's answers never appear
   again. The list can be reviewed and undone at
   Menu > Settings > Blocked users.

6. Removing your own post from the feed immediately
   Today screen > under your answer > "Delete this answer". After a
   confirmation the answer leaves every other user's feed immediately
   (the server marks it removed and the shared timeline view filters it
   out). The confirmation states that you cannot answer the same prompt
   again afterwards.

7. Acting on reports within 24 hours
   A post reported by three different users is hidden from everyone
   automatically; one report is enough if the text matches our
   blocklist. An author whose posts have been hidden three times is
   suspended automatically. In addition we review the moderation queue
   at least once every 24 hours and remove violating posts and suspend
   the accounts responsible. A suspended account can no longer post or
   read, and all of its past answers stop being visible to everyone.
   Our written daily procedure is in the repository as
   docs/moderation-runbook.md.

8. Contact information inside the app
   Menu > Settings > Contact us (the first row of Settings). The
   address nakakei6439@gmail.com is shown on screen as selectable,
   copyable text, and there is a button that opens a prefilled mail
   message. The same contact is also shown on the account-suspended
   screen so an ejected user can appeal. The address appears in the
   Terms of Use and the Privacy Policy as well.

== Guideline 3.1.2 ==

- The custom EULA is now registered in App Store Connect.
- The App Description contains functional links to the Terms of Use and
  the Privacy Policy.
- The subscription screen inside the app (Menu > Plus) shows the price
  and the billing period and now also links to the Terms of Use and the
  Privacy Policy.

  Terms of Use:    https://nakakei6439.github.io/sameq/terms.html
  Privacy Policy:  https://nakakei6439.github.io/sameq/privacy.html
```

---

## Resolution Center への返信（英文）

```
Thank you for the detailed review.

We have implemented all eight precautions listed under Guideline 1.2 in
1.0.3 (8), and resolved Guideline 3.1.2. The App Review Notes for this
build contain a point-by-point list with the exact steps to verify each
one inside the app.

Two notes that may help the review:

First, SameQ is not an anonymous chat app. There are no direct
messages, no conversations, no following and no image uploads. Once a
day everyone answers the same prompt with one short text, and answers
disappear after 24-36 hours. The only content a user can create is
short text, an emoji avatar and an optional nickname.

Second, other users' answers are intentionally locked until you submit
your own answer for the day. This means the Report and Block controls
can only be reached after answering. The App Review Notes describe the
exact sequence of taps.

We have set the age rating to 18+, the terms now state explicitly that
we have no tolerance for objectionable content or abusive users and
that we act on reports within 24 hours, answers and nicknames are
filtered on the device and on the server, users can delete their own
answer at any time, and a contact address is available in the app under
Menu > Settings > Contact us.

Thank you for your time.
```

---

## Resolution Center への返信（和文・必要なら）

```
詳細なレビューをありがとうございます。

Guideline 1.2 に挙げられた8項目すべてを 1.0.3 (8) で実装し、Guideline 3.1.2 も
解消しました。各項目をアプリ内のどこで確認できるかは、App Review Notes に
手順つきで記載しています。

補足を2点申し添えます。

1点目に、SameQ は匿名チャットアプリではありません。ダイレクトメッセージも
会話もフォローも画像投稿もありません。1日1回、全員に同じお題が届き、短い
テキストで1回だけ答えます。回答は24〜36時間で消えます。利用者が作れるのは
短いテキスト、絵文字のアバター、任意のニックネームだけです。

2点目に、他の利用者の回答は、自分がその日の回答を投稿するまで意図的に
ロックされています。そのため通報・ブロックの操作は回答後にのみ到達できます。
App Review Notes に正確なタップ手順を記載しました。

年齢レーティングは 18+ に変更し、規約には不適切なコンテンツおよび迷惑行為を
一切許容しないこと、通報には24時間以内に対応することを明記しました。回答と
ニックネームは端末側とサーバー側の両方でフィルタしています。利用者はいつでも
自分の回答を削除できます。連絡先はアプリ内のメニュー → 設定 → お問い合わせから
確認できます。

よろしくお願いいたします。
```

---

## 提出前チェックリスト

- [ ] 年齢レーティングが **18+** と表示されていることを ASC で目視確認
- [ ] ASC「App情報 → 使用許諾契約」にカスタム EULA を登録
- [ ] 説明文（ja / en-US 両方）の末尾に規約・プライバシーのリンクを追記
- [ ] 追記したリンクが実際に開けることをブラウザで確認
- [ ] App Review Notes を貼る（**タップ手順を必ず含める**）
- [ ] 英語端末のシミュレータで、規約とプライバシーポリシーが英語で表示されることを確認
- [ ] 英語端末で NGワードを含む投稿が拒否されることを確認
- [ ] 自分の回答を削除 → 他ユーザーから消えることを SQL で確認
- [ ] Plus 画面から規約・プライバシーが開けることを確認
- [ ] メニュー → 設定 → お問い合わせ が動くことを確認
