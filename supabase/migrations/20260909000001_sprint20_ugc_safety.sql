-- SameQ スプリント20: 匿名投稿の安全対策（F48-F54 / App Store Guideline 1.2）
--
-- Apple から 1.0.2 (7) が Guideline 1.2（ユーザー生成コンテンツ）でリジェクトされた。
-- 「以下のすべてを実装せよ」として8項目が挙げられており、そのうちサーバー側で
-- 担保すべきものをここにまとめる。
--
--   * 不適切な表現のフィルタ（F48・前提34/35/36）
--     - 端末側だけだと、アプリの画面を通さない経路で送られた文言が世界に出てしまう。
--       サーバー側は「何を経由しても保存させない」ための最後の壁。
--   * 自分の回答の削除（F49・前提1/37）
--     - 行を消さず `status='removed'` にする。行ごと消すと `reports` が
--       `on delete cascade` で道連れになり、通報された投稿者が自分で証拠を
--       消せてしまう。
--   * 通報の自動対処（F50・前提38/39）
--     - 通報3件で自動非表示。本文が禁止語に一致するなら1件で非表示。
--     - 同じ投稿者の投稿が3件以上非表示になったら自動でBAN（運営名義は対象外）。
--
-- 受け皿は既にある: `world_timeline` は `p.status='visible' and u.status='active'`
-- で絞っているので、状態を立てるだけで全ユーザーから即座に消える。
-- ビューの再定義は不要。
--
-- 運営用のアプリ内画面は作らない（前提10・16・40）。運用は
-- `docs/moderation-runbook.md` の SQL を `supabase db query --linked` で打つ。

-- ---------------------------------------------------------------------------
-- 0) posts.body の長さ制約を Plus の上限に揃える
-- ---------------------------------------------------------------------------
-- init.sql の `between 1 and 1000` が Plus の本文上限 2000 文字
-- (`LocalBackend.bodyCharacterLimit(isPlus:)`) と矛盾していた。Plus ユーザーが
-- 1000 文字を超えると、アプリ側の検証を通ったあとサーバーで不可解に落ちる。
alter table public.posts drop constraint if exists posts_body_length;
alter table public.posts add constraint posts_body_length
    check (char_length(btrim(body)) between 1 and 2000);

-- ---------------------------------------------------------------------------
-- 1) users: 運営名義フラグと規約同意の記録
-- ---------------------------------------------------------------------------
alter table public.users add column if not exists is_official boolean not null default false;
alter table public.users add column if not exists terms_version text;
alter table public.users add column if not exists terms_accepted_at timestamptz;

comment on column public.users.is_official is
    '運営名義のアカウント（F47）。自動BANの対象外にするためのフラグ。
     共有の書き手なので、1度の誤爆で運営の回答が全滅するのを避ける（前提39）。';
comment on column public.users.terms_version is
    '同意した利用規約の版（F53）。アプリ側の LegalText.version と同じ文字列。';

-- 運営名義の5アカウント（`ensure_official_answers()` の v_official_ids と同一）。
update public.users
set is_official = true
where id in (
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000004',
    '00000000-0000-0000-0000-000000000005'
);

-- ---------------------------------------------------------------------------
-- 2) prohibited_terms: 禁止表現の辞書
-- ---------------------------------------------------------------------------
-- ここに RLS ポリシーは作らない（= authenticated からは1行も読めない）。
-- 参照するのは security definer の判定関数だけ。辞書そのものが読めると
-- 「どう書けば通るか」の一覧を配ることになるため。
--
-- match_mode:
--   'word'      … 語境界での一致。ラテン文字の語に使う。
--                 これを部分一致にすると class / passed / analysis のような
--                 無関係な語が巻き込まれる（前提34）。
--   'substring' … 部分一致。日本語には語の区切りが無いのでこちらを使う。
create table if not exists public.prohibited_terms (
    term       text        primary key,
    match_mode text        not null,
    category   text        not null,
    created_at timestamptz not null default now(),
    constraint prohibited_terms_mode_check check (match_mode in ('word', 'substring')),
    constraint prohibited_terms_category_check check (
        category in ('discrimination', 'sexual', 'violence', 'crime', 'contact')
    )
);

comment on table public.prohibited_terms is
    'F48 の禁止表現辞書。RLS ポリシーを持たないので authenticated からは読めない。
     参照するのは contains_prohibited_term() だけ。語を追加したら、次のビルドで
     SameQ/Backend/ContentFilter.swift 側にも同じ語を足すこと
     （端末側は「書いている本人にその場で気づかせる」役、サーバー側は
     「何を経由しても保存させない」役。前提35）。';

alter table public.prohibited_terms enable row level security;

-- ---------------------------------------------------------------------------
-- 3) contains_prohibited_term: 判定関数
-- ---------------------------------------------------------------------------
-- 正規化してから照合する:
--   * NFKC        … 全角英字 (Ｆｕｃｋ)・半角カナを標準形へ潰す
--   * lower       … 大文字小文字を吸収
-- 日本語のカタカナ／ひらがなの揺れは、辞書側に両方の表記を入れて吸収する
-- （SQL 側でカナ変換をやると PostgreSQL の標準機能から外れるため）。
create or replace function public.contains_prohibited_term(candidate text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    v_normalized text;
    v_row        record;
begin
    if candidate is null or btrim(candidate) = '' then
        return false;
    end if;

    v_normalized := lower(normalize(candidate, NFKC));

    for v_row in select term, match_mode from public.prohibited_terms loop
        if v_row.match_mode = 'substring' then
            if position(v_row.term in v_normalized) > 0 then
                return true;
            end if;
        else
            -- \y は語境界。term 側に正規表現メタ文字は入れない運用にする。
            if v_normalized ~ ('\y' || v_row.term || '\y') then
                return true;
            end if;
        end if;
    end loop;

    return false;
end $$;

comment on function public.contains_prohibited_term(text) is
    'F48。本文・ニックネームが禁止表現を含むかを返す。辞書を読ませないため
     security definer。どの語に当たったかは返さない（前提36）。';

revoke all on function public.contains_prohibited_term(text) from public;
-- アプリからは直接呼ばせない（当たり判定を総当たりで探れてしまうため）。
-- 呼ぶのはトリガ関数だけ。

-- ---------------------------------------------------------------------------
-- 4) 投稿とニックネームに対するフィルタのトリガ
-- ---------------------------------------------------------------------------
create or replace function public.posts_reject_prohibited()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_is_official boolean;
begin
    -- 運営名義の回答（F47）は出荷前に人が目を通したものなので判定から外す。
    -- ここを通すと、辞書に載った語がたまたま運営回答に含まれていた日に
    -- `ensure_official_answers()` が丸ごと失敗し、その日のタイムラインが
    -- 空になる（＝2回目のリジェクト 2.1(a) の再発）。
    select is_official into v_is_official from public.users where id = new.author_id;
    if coalesce(v_is_official, false) then
        return new;
    end if;

    if public.contains_prohibited_term(new.body) then
        raise exception 'prohibited_body' using errcode = 'P0001';
    end if;
    return new;
end $$;

drop trigger if exists posts_reject_prohibited_trigger on public.posts;
create trigger posts_reject_prohibited_trigger
    before insert on public.posts
    for each row execute function public.posts_reject_prohibited();

create or replace function public.users_reject_prohibited()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.nickname is not null and public.contains_prohibited_term(new.nickname) then
        raise exception 'prohibited_nickname' using errcode = 'P0001';
    end if;
    return new;
end $$;

drop trigger if exists users_reject_prohibited_trigger on public.users;
create trigger users_reject_prohibited_trigger
    before insert or update of nickname on public.users
    for each row execute function public.users_reject_prohibited();

-- ---------------------------------------------------------------------------
-- 5) moderation_actions: 対処の記録
-- ---------------------------------------------------------------------------
-- 「24時間以内に対処した」ことを後から示せるようにするための台帳。
-- RLS ポリシーは作らない（運営が service_role / db query でのみ読む）。
create table if not exists public.moderation_actions (
    id         uuid        primary key default gen_random_uuid(),
    post_id    uuid,
    user_id    uuid,
    action     text        not null,
    source     text        not null,
    note       text,
    created_at timestamptz not null default now(),
    constraint moderation_actions_action_check check (
        action in ('post_removed_by_author', 'post_hidden', 'post_restored',
                   'user_banned', 'user_unbanned')
    ),
    constraint moderation_actions_source_check check (
        source in ('author', 'auto', 'ops')
    )
);

create index if not exists moderation_actions_created_idx
    on public.moderation_actions (created_at desc);

comment on table public.moderation_actions is
    'F50。投稿の非表示・削除・BAN の記録。Apple 1.2 が求める「24時間以内の対処」の
     証跡になる。アプリからは読めない（RLS ポリシーを持たない）。';

alter table public.moderation_actions enable row level security;

-- ---------------------------------------------------------------------------
-- 6) remove_my_post: 自分の回答の削除（F49）
-- ---------------------------------------------------------------------------
-- **RLS の UPDATE ポリシーではなく RPC にする理由**:
-- RLS の with check は「どの列を更新したか」を制限できない。posts に UPDATE を
-- 許した瞬間、クライアントは同じ UPDATE で body を書き換えられる（＝投稿の編集が
-- 可能になり、通報された投稿者が本文を差し替えて逃げられる）。列単位 grant で
-- 塞ぐこともできるが、将来の migration で容易に踏み外す。
-- そこで posts に対するクライアントの権限は INSERT と SELECT のままにして、
-- 状態変更は security definer 関数だけが行う（delete_my_account() と同じ流儀）。
create or replace function public.remove_my_post(target_post uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    update public.posts
    set status = 'removed'
    where id = target_post
      and author_id = auth.uid()
      and status <> 'removed';

    if not found then
        raise exception 'post_not_found_or_not_owned' using errcode = 'P0001';
    end if;

    insert into public.moderation_actions (post_id, user_id, action, source, note)
    values (target_post, auth.uid(), 'post_removed_by_author', 'author', null);
end $$;

comment on function public.remove_my_post(uuid) is
    'F49。自分の回答を status=removed にする。行は残すので通報の記録
     （reports.post_id の参照）と安全ログの30日保持（F34）は壊れない。
     posts_one_per_prompt はそのままなので、削除後に同じお題へ再回答はできない（前提1）。';

revoke all on function public.remove_my_post(uuid) from public;
grant execute on function public.remove_my_post(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 7) 通報の自動対処（F50・前提38/39）
-- ---------------------------------------------------------------------------
-- reports は select-own の RLS なので、件数の集計は security definer からしか
-- できない。ここで数えて閾値を超えたら posts.status を立てる。
create or replace function public.reports_apply_threshold()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_report_count  int;
    v_body          text;
    v_status        text;
    v_author        uuid;
    v_is_official   boolean;
    v_hidden_count  int;
    v_should_hide   boolean := false;
begin
    select p.body, p.status, p.author_id, u.is_official
    into v_body, v_status, v_author, v_is_official
    from public.posts p
        join public.users u on u.id = p.author_id
    where p.id = new.post_id;

    if v_status is null or v_status <> 'visible' then
        return new;   -- 既に消えている／存在しない投稿には何もしない
    end if;

    select count(*) into v_report_count
    from public.reports
    where post_id = new.post_id;

    -- 通報3件で非表示（前提38）。1〜2件では誤通報や「気に入らないだけ」の
    -- 通報と区別できない。
    if v_report_count >= 3 then
        v_should_hide := true;
    end if;

    -- ただし本文が禁止語辞書に一致するなら通報1件で消す。辞書に語を後から
    -- 追加した場合に、すでに出ている投稿へ遡って効かせるため（前提38）。
    if not v_should_hide and public.contains_prohibited_term(v_body) then
        v_should_hide := true;
    end if;

    if not v_should_hide then
        return new;
    end if;

    update public.posts set status = 'hidden' where id = new.post_id;

    insert into public.moderation_actions (post_id, user_id, action, source, note)
    values (new.post_id, v_author, 'post_hidden', 'auto',
            'reports=' || v_report_count);

    -- 同じ投稿者の投稿が3件以上、非表示になったらアカウントを停止する（前提39）。
    -- 1つの投稿への集中通報では停止しない。複数のお題にまたがって繰り返し
    -- 通報されて初めて落ちるので、示し合わせた通報の被害を受けにくい。
    if coalesce(v_is_official, false) then
        return new;   -- 運営名義は自動BANの対象外
    end if;

    select count(*) into v_hidden_count
    from public.posts
    where author_id = v_author and status = 'hidden';

    if v_hidden_count >= 3 then
        update public.users
        set status = 'banned', banned_at = now()
        where id = v_author and status = 'active';

        if found then
            insert into public.moderation_actions (post_id, user_id, action, source, note)
            values (null, v_author, 'user_banned', 'auto',
                    'hidden_posts=' || v_hidden_count);
        end if;
    end if;

    return new;
end $$;

comment on function public.reports_apply_threshold() is
    'F50。通報3件（本文が禁止語に一致するなら1件）で投稿を非表示にし、
     非表示が3件たまった投稿者を停止する。運営名義は自動停止の対象外。
     人間の確認を置き換えるものではなく、運営が確認するまでの時間を埋めるもの（前提40）。';

drop trigger if exists reports_apply_threshold_trigger on public.reports;
create trigger reports_apply_threshold_trigger
    after insert on public.reports
    for each row execute function public.reports_apply_threshold();

-- ---------------------------------------------------------------------------
-- 8) moderation_queue: 運営が毎日見るビュー
-- ---------------------------------------------------------------------------
-- アプリからは読めない（anon / authenticated への grant を与えない）。
create or replace view public.moderation_queue as
select
    p.id                as post_id,
    p.status            as post_status,
    p.author_id,
    u.status            as author_status,
    u.is_official,
    u.emoji,
    u.nickname,
    p.body,
    count(r.id)         as report_count,
    array_agg(distinct r.reason) as reasons,
    min(r.created_at)   as first_reported_at,
    max(r.created_at)   as last_reported_at
from public.reports r
    join public.posts p on p.id = r.post_id
    join public.users u on u.id = p.author_id
group by p.id, p.status, p.author_id, u.status, u.is_official, u.emoji, u.nickname, p.body;

comment on view public.moderation_queue is
    '運営が毎日確認する通報の一覧（docs/moderation-runbook.md）。
     アプリ内に運営用画面は作らない（前提10・16・40）ため、
     supabase db query --linked からのみ参照する。';

revoke all on public.moderation_queue from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 9) 禁止表現の初期辞書
-- ---------------------------------------------------------------------------
-- ラテン文字は 'word'（語境界）、日本語は 'substring'（部分一致）。
-- カタカナ／ひらがなの揺れは両方を行として持つ。
-- 語を足すときは SameQ/Backend/ContentFilter.swift にも同じ語を足すこと。
insert into public.prohibited_terms (term, match_mode, category) values
    -- 英語: 性的
    ('fuck', 'word', 'sexual'),
    ('fucking', 'word', 'sexual'),
    ('fucker', 'word', 'sexual'),
    ('motherfucker', 'word', 'sexual'),
    ('cunt', 'word', 'sexual'),
    ('dick', 'word', 'sexual'),
    ('cock', 'word', 'sexual'),
    ('pussy', 'word', 'sexual'),
    ('blowjob', 'word', 'sexual'),
    ('handjob', 'word', 'sexual'),
    ('creampie', 'word', 'sexual'),
    ('porn', 'word', 'sexual'),
    ('porno', 'word', 'sexual'),
    ('pornhub', 'word', 'sexual'),
    ('hentai', 'word', 'sexual'),
    ('nudes', 'word', 'sexual'),
    ('boobs', 'word', 'sexual'),
    ('tits', 'word', 'sexual'),
    ('anal', 'word', 'sexual'),
    ('jerk off', 'substring', 'sexual'),
    ('cum', 'word', 'sexual'),
    -- 英語: 侮蔑・差別
    ('bitch', 'word', 'discrimination'),
    ('bastard', 'word', 'discrimination'),
    ('asshole', 'word', 'discrimination'),
    ('retard', 'word', 'discrimination'),
    ('retarded', 'word', 'discrimination'),
    ('nigger', 'word', 'discrimination'),
    ('nigga', 'word', 'discrimination'),
    ('faggot', 'word', 'discrimination'),
    ('tranny', 'word', 'discrimination'),
    ('chink', 'word', 'discrimination'),
    ('spic', 'word', 'discrimination'),
    ('kike', 'word', 'discrimination'),
    ('gook', 'word', 'discrimination'),
    ('wetback', 'word', 'discrimination'),
    ('raghead', 'word', 'discrimination'),
    ('subhuman', 'word', 'discrimination'),
    -- 英語: 暴力・自傷の扇動
    ('kill yourself', 'substring', 'violence'),
    ('kys', 'word', 'violence'),
    ('go die', 'substring', 'violence'),
    ('i will kill you', 'substring', 'violence'),
    ('rape', 'word', 'violence'),
    ('rapist', 'word', 'violence'),
    ('lynch', 'word', 'violence'),
    ('genocide', 'word', 'violence'),
    -- 英語: 犯罪の助長
    ('child porn', 'substring', 'crime'),
    ('cp trade', 'substring', 'crime'),
    ('buy drugs', 'substring', 'crime'),
    ('sell drugs', 'substring', 'crime'),
    ('meth for sale', 'substring', 'crime'),
    ('cocaine for sale', 'substring', 'crime'),
    ('hitman', 'word', 'crime'),
    -- 日本語: 侮蔑・差別
    ('死ね', 'substring', 'violence'),
    ('しね', 'substring', 'violence'),
    ('氏ね', 'substring', 'violence'),
    ('殺す', 'substring', 'violence'),
    ('ころす', 'substring', 'violence'),
    ('殺してやる', 'substring', 'violence'),
    ('自殺しろ', 'substring', 'violence'),
    ('消えろ', 'substring', 'violence'),
    ('キチガイ', 'substring', 'discrimination'),
    ('きちがい', 'substring', 'discrimination'),
    ('気違い', 'substring', 'discrimination'),
    ('池沼', 'substring', 'discrimination'),
    ('知障', 'substring', 'discrimination'),
    ('土人', 'substring', 'discrimination'),
    ('部落民', 'substring', 'discrimination'),
    ('穢多', 'substring', 'discrimination'),
    ('非人', 'substring', 'discrimination'),
    ('チョン', 'substring', 'discrimination'),
    ('シナ人', 'substring', 'discrimination'),
    ('支那人', 'substring', 'discrimination'),
    ('在日認定', 'substring', 'discrimination'),
    ('ゴキブリども', 'substring', 'discrimination'),
    ('カタワ', 'substring', 'discrimination'),
    ('かたわ', 'substring', 'discrimination'),
    ('めくら', 'substring', 'discrimination'),
    ('つんぼ', 'substring', 'discrimination'),
    -- 日本語: 性的
    ('セックス', 'substring', 'sexual'),
    ('せっくす', 'substring', 'sexual'),
    ('童貞', 'substring', 'sexual'),
    ('処女膜', 'substring', 'sexual'),
    ('ちんこ', 'substring', 'sexual'),
    ('チンコ', 'substring', 'sexual'),
    ('ちんぽ', 'substring', 'sexual'),
    ('まんこ', 'substring', 'sexual'),
    ('マンコ', 'substring', 'sexual'),
    ('おっぱい揉', 'substring', 'sexual'),
    ('射精', 'substring', 'sexual'),
    ('中出し', 'substring', 'sexual'),
    ('アへ顔', 'substring', 'sexual'),
    ('エロ画像', 'substring', 'sexual'),
    ('エロ動画', 'substring', 'sexual'),
    ('無修正', 'substring', 'sexual'),
    ('援交', 'substring', 'sexual'),
    ('援助交際', 'substring', 'sexual'),
    ('パパ活募集', 'substring', 'sexual'),
    ('風俗嬢', 'substring', 'sexual'),
    ('レイプ', 'substring', 'violence'),
    ('強姦', 'substring', 'violence'),
    ('痴漢', 'substring', 'violence'),
    ('児童ポルノ', 'substring', 'crime'),
    -- 日本語: 犯罪の助長
    ('闇バイト', 'substring', 'crime'),
    ('裏バイト', 'substring', 'crime'),
    ('覚醒剤', 'substring', 'crime'),
    ('大麻売', 'substring', 'crime'),
    ('大麻買', 'substring', 'crime'),
    ('拳銃売', 'substring', 'crime'),
    ('爆弾の作り方', 'substring', 'crime'),
    ('殺人依頼', 'substring', 'crime'),
    ('口座売買', 'substring', 'crime'),
    ('名義貸し募集', 'substring', 'crime'),
    -- 連絡先・外部誘導（個人情報の記載＝規約第4条(4)、スパム対策）
    ('http://', 'substring', 'contact'),
    ('https://', 'substring', 'contact'),
    ('www.', 'substring', 'contact'),
    -- 'line id' は語境界で持つ。部分一致にすると "on|line id|ea" のように
    -- ふつうの英文（online idea）を巻き込む。
    ('line id', 'word', 'contact'),
    ('ラインid', 'substring', 'contact'),
    ('カカオid', 'substring', 'contact')
on conflict (term) do nothing;
