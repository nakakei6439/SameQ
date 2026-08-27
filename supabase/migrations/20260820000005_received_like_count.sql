-- SameQ スプリント12 attempt 12: eval-8.md [1] の修正
--
-- 背景:
--   attempt 11 で `received_like_count` 関数と `liked_authors_view` を
--   既に本番適用済みの `20260819000004_server_connection.sql` の末尾に追記した。
--   Supabase のマイグレーションは適用済みファイルに `supabase db push` を
--   叩いても再適用されず（"Remote database is up to date."）、
--   `received_like_count` が本番に存在しないため `POST /rest/v1/rpc/received_like_count`
--   が 404 PGRST202 を返して `receivedLikeCount` が無言で 0 にフォールスルーする。
--
-- 修正:
--   関数とビューを **新規マイグレーションファイル** に切り出す。
--   これにより `supabase db push` で初めて本番に適用される。
--   適用後の状態:
--     - `public.received_like_count(target_post uuid)` が存在し、
--       `SupabaseBackend.receivedLikeCount(forPostID:)` から
--       `POST /rest/v1/rpc/received_like_count` で呼べるようになる。
--     - `public.liked_authors_view` が存在し、`received_like_count` の動作確認 /
--       デバッグオーバーレイ / サポート問い合わせに使える。
--
-- 注意:
--   * 既に同じ関数 / ビューを migration 4 にも定義しているが
--     一方は `create or replace` で冪等なので、適用順による衝突は無い。
--     むしろ「両方のファイルで定義がある」状態のほうが、本番上で関数が
--     確実に存在することを二重に担保できる。
--   * `revoke all ... from public; grant execute ... to authenticated;`
--     も両方のファイルに置く。`grant` は冪等。
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- received_like_count(post_id) — 自分の投稿の受信いいね件数 (F35・受け入れ条件3)
-- ---------------------------------------------------------------------------
-- `likes_select_own` の RLS は `user_id = auth.uid()` だけで、本人が付けたいいね
-- 行しか読めない。そのため `GET /rest/v1/likes?post_id=eq.<自分の投稿>` は
-- 自分が押した行しか返さず、他人が付けたいいねは 1 件も数えられない
-- (attempt 11: eval-7.md [1] b の修正 / attempt 12: eval-8.md [1] の修正で
-- 新規マイグレーションに切り出し)。
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
