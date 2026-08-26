-- SameQ スプリント12: サーバー接続（F35）
--
-- 変更点:
--   * posts に `decorations` を追加（Plus 限定装飾の復元 / F29 / F30）。
--     `20260817000001_init.sql` で装飾カラムは未定義のため、ここで追加する。
--   * world_timeline ビューに `body_language` / `created_at` / `expires_at` /
--     `decorations` を追加（端末内翻訳・表示期限判定・装飾復元の必要条件）
--   * `liked_authors_view` を追加（デバッグ用、自分の投稿に誰がライクしたかの集計）
--
-- 注意: スプリント04 の `20260818000003_report_block.sql` で `world_timeline` は
--       通報済み / ブロック中を除外する形に更新されているが、必要な列が追加で
--       必要になったため、本ファイルで `CREATE OR REPLACE VIEW` する。
--       アプリはまだ `LocalBackend` で動いていたが、本マイグレーションを
--       `supabase db push` したあとに `SupabaseBackend` への切り替えを行う。
--
-- 注意: attempt 6 でこのファイル自体に欠陥があったことを修正した。
--       旧版は `posts.decorations` を SELECT していたが `ALTER TABLE ... ADD COLUMN`
--       が無いため `column posts.decorations does not exist` で `db push` が
--       失敗する状態だった（eval-4.md [3]）。`decorations` をここで追加する。

-- ---------------------------------------------------------------------------
-- posts.decorations: 装飾情報（Plus 限定絵文字・文字装飾・吹き出し / F30）
-- ---------------------------------------------------------------------------
-- 端末内翻訳のため送るのは本文だけだが、装飾は表示側で本文上に重ねる必要があるので
-- サーバー側にも置く（Free ユーザーにも装飾付き投稿がそのまま読めることを担保）。
-- 形式は jsonb（`PostDecoration` の JSON 表現）。既存行は空配列で初期化する。
alter table public.posts
    add column if not exists decorations jsonb not null default '[]'::jsonb;

comment on column public.posts.decorations is
    'Plus 限定の装飾（F30）。本文に重ねて表示される。jsonb。Free ユーザーも装飾付き
     投稿を全文読めるよう装飾データ自体も配信される。';

-- ---------------------------------------------------------------------------
-- world_timeline: 表示に必要な列を追加（F18 / F20 / F22 / F29 / F30 用）
-- ---------------------------------------------------------------------------
create or replace view public.world_timeline
with (security_invoker = off) as
select
    p.id,
    p.prompt_id,
    p.author_id,
    u.emoji    as author_emoji,
    u.nickname as author_nickname,
    p.body,
    p.body_language,
    p.created_at,
    p.expires_at,
    p.decorations
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
    '他人の回答はここからしか読めない。F18/F20/F22/F29/F30 で必要な列（body_language /
     created_at / expires_at / decorations）を含む。未回答なら0件（F05）。
     ブロック中の相手と通報済みの回答は返さない（F13 / F14）。';

revoke all on public.world_timeline from anon;
grant select on public.world_timeline to authenticated;

-- ---------------------------------------------------------------------------
-- likes DELETE の RLS ポリシー（スプリント12 で明示的に必要になった）
-- ---------------------------------------------------------------------------
-- `20260817000001_init.sql` で既に定義済みなので、ここでは再定義しない。
-- 万一欠けていた場合に備えて re-create しておく。
drop policy if exists likes_delete_own on public.likes;
create policy likes_delete_own on public.likes
    for delete to authenticated
    using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- viewed_posts DELETE の RLS ポリシー（念のため）
-- ---------------------------------------------------------------------------
-- スプリント12 で「既読のリセット」操作（`-SameQResetViewed` 相当）を
-- ユーザー単位で行えるようにするため、自分の行だけ DELETE 許可。
drop policy if exists viewed_delete_own on public.viewed_posts;
create policy viewed_delete_own on public.viewed_posts
    for delete to authenticated
    using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- safety_logs ビュー（参考表示用、F34 の 30 日保持と組み合わせる）
-- ---------------------------------------------------------------------------
-- 通報記録を `post_expires_at + 30 日` まで残す仕組みを SQL レベルで
-- 表現したもの。アプリからは reports テーブルを直接見る。
create or replace view public.safety_logs
with (security_invoker = off) as
select
    r.id,
    r.reporter_id,
    r.post_id,
    r.reason,
    r.created_at,
    p.expires_at as post_expires_at
from public.reports r
    left join public.posts p on p.id = r.post_id;

comment on view public.safety_logs is
    '通報記録 + 投稿の表示期限。30 日の保持期間計算に使う (F34)。';

revoke all on public.safety_logs from anon;
grant select on public.safety_logs to authenticated;
