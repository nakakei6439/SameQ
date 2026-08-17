-- SameQ スプリント01 のスキーマ
--
-- 対象: users / prompts / posts / likes / viewed_posts
-- 方針:
--   * 匿名認証（auth.users）の uid をそのまま public.users.id として使う
--   * 他人の回答は「自分がそのお題に回答済みのときだけ」見える（F05 をサーバー側でも担保）
--   * 投稿の編集・削除は不可（update / delete のポリシーを作らない）
--
-- 注意: このファイルは Supabase クラウドプロジェクト未作成のため未適用・未検証。
--       ローカル検証には Docker が必要だが本環境に無い（PROGRESS.md のブロッカー参照）。

-- ---------------------------------------------------------------------------
-- users: 匿名アカウント（F02）
-- ---------------------------------------------------------------------------
create table if not exists public.users (
    id          uuid primary key,           -- auth.uid() と同一値を入れる
    emoji       text        not null,
    nickname    text,                       -- 未設定を許す（絵文字のみ表示）
    created_at  timestamptz not null default now(),
    status      text        not null default 'active',
    banned_at   timestamptz,
    constraint users_status_check check (status in ('active', 'banned')),
    constraint users_emoji_length check (char_length(emoji) between 1 and 8),
    constraint users_nickname_length check (nickname is null or char_length(nickname) <= 20)
);

comment on table public.users is '匿名アカウント。メール・電話番号は保持しない。';
comment on column public.users.status is 'active / banned。BAN の切り替えは運営がサーバー側で行う（F16）。';

-- ---------------------------------------------------------------------------
-- prompts: 世界共通のお題（F03）
-- ---------------------------------------------------------------------------
create table if not exists public.prompts (
    id          text        primary key,    -- 例: prompt_001（世界共通）
    text        text        not null,
    starts_at   timestamptz not null,
    ends_at     timestamptz not null,
    created_at  timestamptz not null default now(),
    constraint prompts_period_check check (ends_at > starts_at)
);

comment on table public.prompts is '世界共通のお題。スプリント01では運用側が用意した固定の1件のみ。';

-- 同時に有効なお題は常に1つだけ（置いた前提 3）
create index if not exists prompts_period_idx on public.prompts (starts_at, ends_at);

-- ---------------------------------------------------------------------------
-- posts: お題への回答（F04）
-- ---------------------------------------------------------------------------
create table if not exists public.posts (
    id            uuid        primary key default gen_random_uuid(),
    prompt_id     text        not null references public.prompts (id) on delete cascade,
    author_id     uuid        not null references public.users (id) on delete cascade,
    body          text        not null,
    body_language text        not null,     -- 翻訳可否の判定にのみ使う。公開表示には使わない
    created_at    timestamptz not null default now(),
    expires_at    timestamptz not null,     -- 表示期限。お題の終了時刻に揃える（F10）
    status        text        not null default 'visible',
    constraint posts_status_check check (status in ('visible', 'hidden', 'removed')),
    constraint posts_body_length check (char_length(btrim(body)) between 1 and 1000),
    -- 1つのお題につき1投稿（F17 / 置いた前提 1）
    constraint posts_one_per_prompt unique (prompt_id, author_id)
);

comment on column public.posts.body_language is '翻訳可否の判定にのみ内部利用する。公開表示には使わない。';

create index if not exists posts_prompt_idx on public.posts (prompt_id, expires_at);

-- ---------------------------------------------------------------------------
-- likes: いいね（F07）
-- ---------------------------------------------------------------------------
create table if not exists public.likes (
    user_id    uuid        not null references public.users (id) on delete cascade,
    post_id    uuid        not null references public.posts (id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (user_id, post_id)
);

comment on table public.likes is '唯一のコミュニケーション。ランキングには使わない。取り消し可能。';

-- ---------------------------------------------------------------------------
-- viewed_posts: 既読（F12 / スプリント03 で使用）
-- テーブルだけ先に用意し、スプリント01のアプリからは書き込まない。
-- ---------------------------------------------------------------------------
create table if not exists public.viewed_posts (
    user_id   uuid        not null references public.users (id) on delete cascade,
    post_id   uuid        not null references public.posts (id) on delete cascade,
    viewed_at timestamptz not null default now(),
    primary key (user_id, post_id)
);

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.users        enable row level security;
alter table public.prompts      enable row level security;
alter table public.posts        enable row level security;
alter table public.likes        enable row level security;
alter table public.viewed_posts enable row level security;

-- users: 自分の行だけ読み書きできる。他人のプロフィールは world_timeline ビュー経由でしか見えない。
create policy users_select_own on public.users
    for select to authenticated
    using (id = auth.uid());

create policy users_insert_own on public.users
    for insert to authenticated
    with check (id = auth.uid());

create policy users_update_own on public.users
    for update to authenticated
    using (id = auth.uid())
    with check (id = auth.uid() and status = 'active');

-- prompts: 認証済みなら読める（有効期間での絞り込みはスプリント02）
create policy prompts_select_all on public.prompts
    for select to authenticated
    using (true);

-- posts: 自分の投稿だけ直接読める。他人の投稿は world_timeline ビューからしか読めない。
create policy posts_select_own on public.posts
    for select to authenticated
    using (author_id = auth.uid());

create policy posts_insert_own on public.posts
    for insert to authenticated
    with check (
        author_id = auth.uid()
        and exists (
            select 1 from public.users u
            where u.id = auth.uid() and u.status = 'active'
        )
    );

-- 編集・削除は不可（置いた前提 1）のため update / delete のポリシーは作らない。

-- likes: 自分のいいねだけ
create policy likes_select_own on public.likes
    for select to authenticated
    using (user_id = auth.uid());

create policy likes_insert_own on public.likes
    for insert to authenticated
    with check (user_id = auth.uid());

create policy likes_delete_own on public.likes
    for delete to authenticated
    using (user_id = auth.uid());

-- viewed_posts: 自分の既読だけ
create policy viewed_select_own on public.viewed_posts
    for select to authenticated
    using (user_id = auth.uid());

create policy viewed_insert_own on public.viewed_posts
    for insert to authenticated
    with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- world_timeline: 世界タイムラインの唯一の入口（F05 / F06）
--
-- security_invoker = off（= definer）にして、posts / users の RLS を通さずに
-- このビューの where 句だけで公開範囲を決める。
--   * 自分がそのお題に回答済みでなければ 1 件も返らない
--   * 自分の投稿は返らない
--   * BAN されたユーザー・非表示投稿・期限切れ投稿は返らない
--   * 投稿者の国・言語・投稿時刻は返さない（body_language も出さない）
-- ---------------------------------------------------------------------------
create or replace view public.world_timeline
with (security_invoker = off) as
select
    p.id,
    p.prompt_id,
    p.author_id,
    u.emoji    as author_emoji,
    u.nickname as author_nickname,
    p.body
from public.posts p
    join public.users u on u.id = p.author_id
where p.status = 'visible'
  and u.status = 'active'
  and p.expires_at > now()
  and p.author_id <> auth.uid()
  and exists (
      select 1
      from public.posts mine
      where mine.prompt_id = p.prompt_id
        and mine.author_id = auth.uid()
  );

comment on view public.world_timeline is
    '他人の回答はここからしか読めない。自分がそのお題に回答済みでなければ 0 件を返す（F05）。';

revoke all on public.world_timeline from anon;
grant select on public.world_timeline to authenticated;
