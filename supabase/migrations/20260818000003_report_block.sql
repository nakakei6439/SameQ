-- SameQ スプリント04 のスキーマ（F13 通報 / F14 ブロック / F15 ブロック管理）
--
-- 方針:
--   * 通報とブロックは「自分の記録」。相手には一切見えない（select ポリシーは自分の行のみ）
--   * 通報した回答・ブロックした相手の回答は world_timeline から外す
--   * ブロック一覧に相手の国・言語・本文は含めない（絵文字とニックネームだけを返す）
--
-- 注意: アプリはまだ LocalBackend で動いており、このスキーマは未使用。
--       SupabaseBackend 実装時に world_timeline の絞り込みと合わせて検証すること。

-- ---------------------------------------------------------------------------
-- reports: 通報（F13）
-- ---------------------------------------------------------------------------
create table if not exists public.reports (
    id           uuid        primary key default gen_random_uuid(),
    reporter_id  uuid        not null references public.users (id) on delete cascade,
    post_id      uuid        not null references public.posts (id) on delete cascade,
    reason       text        not null,
    created_at   timestamptz not null default now(),
    constraint reports_reason_check check (
        reason in ('politics', 'religion', 'discrimination', 'sexual', 'crime', 'privacy', 'other')
    ),
    -- 同じ回答を何度通報しても記録は1件（連打対策はスプリント05）
    constraint reports_one_per_post unique (reporter_id, post_id)
);

comment on table public.reports is
    '通報の記録（F13）。相手には見えない。表示期限後も安全ログとして保持する（F34 / スプリント11）。';

create index if not exists reports_post_idx on public.reports (post_id);

-- ---------------------------------------------------------------------------
-- blocks: ブロック（F14 / F15）
-- ---------------------------------------------------------------------------
create table if not exists public.blocks (
    blocker_id  uuid        not null references public.users (id) on delete cascade,
    blocked_id  uuid        not null references public.users (id) on delete cascade,
    created_at  timestamptz not null default now(),
    primary key (blocker_id, blocked_id),
    -- 自分自身はブロックできない
    constraint blocks_not_self check (blocker_id <> blocked_id)
);

comment on table public.blocks is
    'ブロック（F14）。解除するまで残る。相手には見えない。';

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.reports enable row level security;
alter table public.blocks  enable row level security;

-- reports: 自分が出した通報だけ。取り消しは作らない（安全ログとして残す）。
create policy reports_select_own on public.reports
    for select to authenticated
    using (reporter_id = auth.uid());

create policy reports_insert_own on public.reports
    for insert to authenticated
    with check (
        reporter_id = auth.uid()
        and post_id not in (select id from public.posts where author_id = auth.uid())
    );

-- blocks: 自分のブロックだけ。解除できる（F15）。
create policy blocks_select_own on public.blocks
    for select to authenticated
    using (blocker_id = auth.uid());

create policy blocks_insert_own on public.blocks
    for insert to authenticated
    with check (blocker_id = auth.uid());

create policy blocks_delete_own on public.blocks
    for delete to authenticated
    using (blocker_id = auth.uid());

-- ---------------------------------------------------------------------------
-- world_timeline: 通報済みの回答とブロック中の相手を外す（F11 の取得条件に追加）
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
  and not exists (
      select 1 from public.blocks b
      where b.blocker_id = auth.uid() and b.blocked_id = p.author_id
  )
  and not exists (
      select 1 from public.reports r
      where r.reporter_id = auth.uid() and r.post_id = p.id
  )
  and exists (
      select 1
      from public.posts mine
      where mine.prompt_id = p.prompt_id
        and mine.author_id = auth.uid()
  );

comment on view public.world_timeline is
    '他人の回答はここからしか読めない。未回答なら0件（F05）。ブロック中の相手と通報済みの回答は返さない（F13 / F14）。';

revoke all on public.world_timeline from anon;
grant select on public.world_timeline to authenticated;

-- ---------------------------------------------------------------------------
-- blocked_authors: ブロック一覧（F15）
--
-- 相手を特定できる情報を渡さないために、返すのは絵文字とニックネームだけ。
-- 国・言語・回答本文・投稿時刻は含めない。
-- ---------------------------------------------------------------------------
create or replace view public.blocked_authors
with (security_invoker = off) as
select
    b.blocked_id as id,
    u.emoji,
    u.nickname,
    b.created_at as blocked_at
from public.blocks b
    join public.users u on u.id = b.blocked_id
where b.blocker_id = auth.uid();

comment on view public.blocked_authors is
    'ブロック一覧（F15）。絵文字とニックネームだけを返す。国・言語・本文は返さない。';

revoke all on public.blocked_authors from anon;
grant select on public.blocked_authors to authenticated;
