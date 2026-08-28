-- SameQ 新機能: 運営お知らせ（announcements）
--
-- 背景:
--   ハンバーガーメニューの通知画面（アプリ通知 / 運営お知らせの2タブ）のうち
--   「運営お知らせ」タブは実データを持つ必要がある。運営が投稿した告知文を
--   全ユーザーへ配信するだけの読み取り専用フィードとして実装する。
--
-- 方針（`prompts` テーブル・migration 20260817000001_init.sql の踏襲）:
--   * アプリ内に投稿・編集・削除 UI は一切作らない
--     （.product/spec.md 前提「アプリ内に運営用画面は作らない」）。
--   * RLS は select のみ許可し、insert/update/delete のポリシーを意図的に
--     作らない。RLS 有効時にポリシーが無ければ全操作がデフォルト拒否される
--     ため、書き込みは service_role（直接 SQL・Supabase ダッシュボード経由）
--     でのみ可能になる。
--   * 掲載順は published_at 降順（新しい順）。
--
-- 注意: このファイルは Supabase クラウドプロジェクト未適用のため未検証
--       （既存 migration と同様の注記）。
-- ---------------------------------------------------------------------------

create table if not exists public.announcements (
    id           uuid        primary key default gen_random_uuid(),
    title        text        not null,
    body         text        not null,
    published_at timestamptz not null default now(),
    created_at   timestamptz not null default now(),
    constraint announcements_title_length check (char_length(btrim(title)) between 1 and 200),
    constraint announcements_body_length check (char_length(btrim(body)) between 1 and 4000)
);

comment on table public.announcements is
    '運営からのお知らせ。読み取り専用（insert/update/delete のポリシーは意図的に無い）。管理者が直接 SQL / dashboard から投入する。';

create index if not exists announcements_published_at_idx
    on public.announcements (published_at desc);

alter table public.announcements enable row level security;

-- 認証済みなら誰でも読める。insert/update/delete のポリシーは作らない
-- （デフォルト拒否 = 管理者のみ書き込み可能）。
create policy announcements_select_all on public.announcements
    for select to authenticated
    using (true);
