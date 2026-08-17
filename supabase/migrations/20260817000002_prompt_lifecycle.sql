-- SameQ スプリント02: お題のライフサイクルと投稿の寿命（F08 / F09 / F10）
--
-- 変更点:
--   * お題は「いま有効なものだけ」読める（有効期間外はお題待ち画面になる）
--   * お題の有効期間どうしが重ならないことをDBで保証する（置いた前提3: 常に1つだけ有効）
--   * 投稿の表示期限は所属するお題の終了時刻に揃える（置いた前提2 / F10）
--
-- 注意: 20260817000001_init.sql は Supabase クラウドへ適用済みだが、
--       このファイルはまだ適用していない。アプリは現在 LocalBackend で動いており、
--       Supabase への接続切り替えは未着手（PROGRESS.md のブロッカー B01 参照）。

-- ---------------------------------------------------------------------------
-- 有効期間の重複禁止（常に1つだけ有効）
-- ---------------------------------------------------------------------------
create extension if not exists btree_gist;

alter table public.prompts
    drop constraint if exists prompts_no_overlap;

alter table public.prompts
    add constraint prompts_no_overlap
    exclude using gist (tstzrange(starts_at, ends_at, '[)') with &&);

comment on table public.prompts is
    '世界共通のお題。有効期間は既定28時間で、同時に有効なお題は常に1つだけ（置いた前提2・3）。';

-- ---------------------------------------------------------------------------
-- prompts: 有効期間中のお題だけを返す（F09）
-- ---------------------------------------------------------------------------
drop policy if exists prompts_select_all on public.prompts;

create policy prompts_select_active on public.prompts
    for select to authenticated
    using (starts_at <= now() and ends_at > now());

-- ---------------------------------------------------------------------------
-- posts: 表示期限はお題の終了時刻に揃える（F10）
-- アプリ側の値を信用せず、DB 側でも揃える。
-- ---------------------------------------------------------------------------
create or replace function public.posts_set_expiry()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    select p.ends_at into new.expires_at
    from public.prompts p
    where p.id = new.prompt_id;

    if new.expires_at is null then
        raise exception 'unknown prompt: %', new.prompt_id;
    end if;

    -- 有効期間外のお題には投稿させない（開始前・終了後）
    if not exists (
        select 1 from public.prompts p
        where p.id = new.prompt_id
          and p.starts_at <= now()
          and p.ends_at > now()
    ) then
        raise exception 'prompt is not active: %', new.prompt_id;
    end if;

    return new;
end;
$$;

drop trigger if exists posts_set_expiry_trigger on public.posts;

create trigger posts_set_expiry_trigger
    before insert on public.posts
    for each row execute function public.posts_set_expiry();

comment on column public.posts.expires_at is
    '表示期限。お題の終了時刻に揃える（F10）。トリガーで自動設定するのでクライアントは指定不要。';
