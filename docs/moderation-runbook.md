# 通報対応ランブック（運営用）

App Store ガイドライン 1.2 は「通報を受けたコンテンツに **24時間以内**に対応し、
違反コンテンツを削除し、投稿したユーザーを排除すること」を求めている。
SameQ は前提10・16 のとおり**アプリ内に運営用画面を作らない**ので、対応はここに書いた
SQL をサーバーに対して直接打つ形で行う。

## 前提

- 書き込み経路は Supabase CLI のみ。`.env.local` に service_role キーは置いていないため、
  REST API 経由の curl では書き込めない（`CLAUDE.md` 参照）。
- 実行方法: `supabase db query --linked "<SQL>"` または
  `supabase db query --linked -f <SQLファイル>`
- 自動化されている部分: 同じ投稿に**通報が3件**集まると `posts.status` が自動で
  `'hidden'` になり、全ユーザーのタイムラインから消える。
  **自動 BAN は行わない**（誤通報による冤罪を避けるため、BAN は必ず人が判断する）。

## 毎日やること（24時間以内の対応の実体）

1日1回、以下の 1→2→3 を順に実行する。

### 1. 未対応の通報を一覧する

```sql
select
    p.id            as post_id,
    p.status        as post_status,
    p.author_id,
    u.status        as author_status,
    u.emoji,
    u.nickname,
    p.body,
    count(r.id)     as report_count,
    array_agg(distinct r.reason) as reasons,
    min(r.created_at) as first_reported_at,
    max(r.created_at) as last_reported_at
from public.reports r
    join public.posts p on p.id = r.post_id
    join public.users u on u.id = p.author_id
where p.status = 'visible'          -- 自動非表示になっていないものだけ
group by p.id, p.status, p.author_id, u.status, u.emoji, u.nickname, p.body
order by count(r.id) desc, min(r.created_at) asc;
```

`report_count` が 3 未満でも、本文を読んで違反が明らかなら次の手順で消す。
**通報が1件でも、内容が規約第4条に触れていれば消す。件数はあくまで自動処理の閾値であり、
人の判断を待つ理由にはしない。**

### 2. 違反している投稿を消す

```sql
update public.posts
set status = 'hidden'
where id = '<post_id>';
```

`world_timeline` ビューが `p.status = 'visible'` で絞っているので、この 1 行で
**全ユーザーのタイムラインから即座に消える**。行自体は残るので、安全ログとしての
保持（F34・目安30日）とその後の自動削除はこれまでどおり働く。

### 3. 違反した利用者を排除する

投稿の内容が悪質な場合、または同じ利用者が繰り返している場合は BAN する。

```sql
update public.users
set status = 'banned',
    banned_at = now()
where id = '<author_id>';
```

BAN された利用者は次回起動時に `current_user_status()` が `'banned'` を返し、
BAN 画面に固定されて投稿も閲覧もできなくなる。`world_timeline` は
`u.status = 'active'` で絞っているので、その利用者の**過去の投稿もすべて**
全ユーザーから見えなくなる。

## 参考: 状況を確認するための SQL

### ある利用者の投稿をすべて見る

```sql
select id, prompt_id, status, created_at, expires_at, body
from public.posts
where author_id = '<author_id>'
order by created_at desc;
```

### 自動非表示になった投稿を確認する

```sql
select p.id, p.author_id, p.body, count(r.id) as report_count
from public.posts p
    join public.reports r on r.post_id = p.id
where p.status = 'hidden'
group by p.id, p.author_id, p.body
order by count(r.id) desc;
```

### BAN を解除する（誤って BAN した場合）

```sql
update public.users
set status = 'active',
    banned_at = null
where id = '<user_id>';
```

### 投稿の非表示を解除する（誤判定だった場合）

```sql
update public.posts
set status = 'visible'
where id = '<post_id>' and status = 'hidden';
```

> `status = 'removed'` は**利用者本人が自分で削除した**印なので、運営が
> `'visible'` に戻してはならない。戻してよいのは `'hidden'`（運営または
> 自動処理が消したもの）だけ。

## 状態の意味

| テーブル | 値 | 意味 |
|---|---|---|
| `posts.status` | `visible` | 通常。表示期限内なら他ユーザーから読める |
| | `hidden` | 運営または通報3件の自動処理で非表示にした |
| | `removed` | **利用者本人が削除した**。運営は戻さない |
| `users.status` | `active` | 通常 |
| | `banned` | BAN 済み。投稿・閲覧とも不可。過去の投稿も全て見えなくなる |
