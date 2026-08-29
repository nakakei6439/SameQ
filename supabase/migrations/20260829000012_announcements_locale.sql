-- SameQ 運営お知らせ: 言語別配信への対応（2026-08-29追記）
--
-- 背景:
--   `announcements` テーブル（20260829000011）には言語の区別が無く、投稿した文章が
--   端末言語に関わらず全ユーザーへそのまま表示されていた。SameQ は UI 自体が
--   日本語／英語を切り替える作り（`L10n.isJapanese`）なので、お知らせも同じ基準で
--   出し分けられるようにする。
--
-- 方針:
--   * `locale` 列を追加（'ja' / 'en' の2値のみ。アプリの `L10n.isJapanese` 判定と
--     1対1で対応させる。フランス語などそれ以外の端末は既存どおり英語に丸められる）。
--   * 既存行があれば 'ja' を既定値として埋める（後方互換）。
--   * アプリ側は自分の端末言語に一致する行だけを取得する
--     （`SupabaseBackend.announcements(locale:)` 参照）。
--   * 「同じお知らせ」を2言語で出す場合は、管理者が ja/en 2行を別々に投入する
--     （1行に複数言語を持たせるのではなく、行を分ける）。

alter table public.announcements
    add column if not exists locale text not null default 'ja';

alter table public.announcements
    add constraint announcements_locale_check check (locale in ('ja', 'en'));

comment on column public.announcements.locale is
    'この告知を表示する端末言語。ja または en の2値のみ。アプリの L10n.isJapanese と対応。';

-- 言語ごとの新しい順取得に使う複合インデックス（既存の published_at 単独インデックスと役割が違う）。
create index if not exists announcements_locale_published_at_idx
    on public.announcements (locale, published_at desc);
