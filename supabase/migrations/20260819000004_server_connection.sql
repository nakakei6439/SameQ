-- SameQ スプリント12: サーバー接続（F35）
--
-- 変更点:
--   * posts に `decorations` を追加（Plus 限定装飾の復元 / F29 / F30）。
--     `20260817000001_init.sql` で装飾カラムは未定義のため、ここで追加する。
--   * world_timeline ビューに `body_language` / `created_at` / `expires_at` /
--     `decorations` を追加（端末内翻訳・表示期限判定・装飾復元の必要条件）
--   * `liked_authors_view` を追加（デバッグ用、自分の投稿に誰がライクしたかの集計）
--   * `received_like_count(post_id)` を追加（attempt 11: eval-7.md [1] b）。
--     `likes_select_own`（`user_id = auth.uid()`）の RLS だけでは他人のいいね行を
--     読めず、「受信いいね数」が常に 0 になる。`security definer` 関数で集計を
--     バイパスし、自分の投稿についてだけ件数を返す。
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

-- ---------------------------------------------------------------------------
-- received_like_count(post_id) — 自分の投稿の受信いいね件数 (F35・受け入れ条件3)
-- ---------------------------------------------------------------------------
-- `likes_select_own` の RLS は `user_id = auth.uid()` だけで、本人が付けたいいね
-- 行しか読めない。そのため `GET /rest/v1/likes?post_id=eq.<自分の投稿>` は
-- 自分が押した行しか返さず、他人が付けたいいねは 1 件も数えられない
-- (attempt 11: eval-7.md [1] b の修正)。
--
-- ここで `security definer` の SQL 関数として集計を提供し、PostgREST の
-- `/rest/v1/rpc/received_like_count` 経由でクライアントから呼べるようにする。
-- 関数本体では:
--   * `auth.uid()` が NULL のときは 0 を返す（未ログインで叩かれた場合の安全弁）
--   * `target_post` が本人の投稿（`author_id = auth.uid()`）であることを確認し、
--     そうでなければ 0 を返す（他人の投稿の件数は漏らさない）
--   * `target_post` が `visible` であることを確認（削除済み・通報済みを除外）
--   * 上記条件を満たせば、対象投稿の `likes` 行件数を返す（RLS バイパス）
--
-- この関数だけ `security definer` なので、`likes` の SELECT ポリシーには影響しない。
create or replace function public.received_like_count(target_post uuid)
returns integer
language sql
security definer
set search_path = public
stable
as $$
    with mine as (
        select 1
        from public.posts p
        where p.id = target_post
          and p.author_id = auth.uid()
          and p.status = 'visible'
    )
    select coalesce(
        (
            select count(*)
            from public.likes l
            where l.post_id = target_post
        ),
        0
    )
    where exists (select 1 from mine);
$$;

comment on function public.received_like_count(uuid) is
    '自分の投稿に付いたいいねの件数を返す（F35・受け入れ条件3）。RLS を
     バイパスして集計するが、対象が本人の投稿であり `status = visible` の
     範囲でなければ 0 を返す。`POST /rest/v1/rpc/received_like_count` で
     SupabaseBackend.receivedLikeCount(forPostID:) から呼ばれる。';

-- この関数の呼び出しは本人の認証済みセッションでしか意味がないため、`anon` には
-- 実行権を渡さない（呼び出し時に 401/permission denied になる）。
revoke all on function public.received_like_count(uuid) from public;
grant execute on function public.received_like_count(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- liked_authors_view — 自分の投稿に誰がライクしたか (デバッグ用)
-- ---------------------------------------------------------------------------
-- attempt 11（eval-7.md [1] b）で追加。`received_like_count` の隣で動作確認用に
-- 用意。デバッグオーバーレイやサポート問い合わせで「誰からいいねが付いたか」を
-- 確認するために使う。RLS をバイパスするため `security_invoker = off`。
create or replace view public.liked_authors_view
with (security_invoker = off) as
select
    l.post_id,
    l.user_id      as liker_id,
    u.emoji        as liker_emoji,
    u.nickname     as liker_nickname,
    l.created_at   as liked_at
from public.likes l
    join public.users u on u.id = l.user_id
where exists (
    select 1
    from public.posts p
    where p.id = l.post_id
      and p.author_id = auth.uid()
);

comment on view public.liked_authors_view is
    '自分の投稿に対する「誰がいつライクしたか」を author_id = auth.uid() で
     絞り込んだもの。`received_like_count` の動作確認・デバッグ・サポート用
     （一般ユーザー向け UI には出さない）。RLS をバイパスする集計用ビューの
     サンプルとして残してある。';

revoke all on public.liked_authors_view from anon;
grant select on public.liked_authors_view to authenticated;
