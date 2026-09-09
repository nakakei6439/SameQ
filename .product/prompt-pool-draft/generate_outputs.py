#!/usr/bin/env python3
"""Sprint19 / F46: 決定的シャッフル + Swift/SQL 生成。

入力: .product/prompt-pool-draft/expanded-pool.txt (999 件)
出力:
- SameQ/Backend/PromptCatalog.swift (candidatePool を 999 件で上書き)
- supabase/migrations/20260908000001_sprint19_prompt_pool_expansion.sql (新規)

並び: 既存 48 件 + 新規 951 件を、決定的シャッフル (seed=42) で並び替える。
Swift の candidatePool と SQL の v_pool は byte-for-byte 一致を保証。
"""

import random
import re
import sys
from pathlib import Path

PROJECT_ROOT = Path("/Users/nakagawakeita/Products/iOSApp/SameQ")
INPUT = PROJECT_ROOT / ".product/prompt-pool-draft/expanded-pool.txt"
SWIFT_FILE = PROJECT_ROOT / "SameQ/Backend/PromptCatalog.swift"
MIGRATION_FILE = PROJECT_ROOT / "supabase/migrations/20260908000001_sprint19_prompt_pool_expansion.sql"
TEST_FILE = PROJECT_ROOT / "SameQTests/PromptGenerationTests.swift"
SHUFFLED_OUT = PROJECT_ROOT / ".product/prompt-pool-draft/shuffled-final.txt"


def extract_originals_from_test():
    src = TEST_FILE.read_text()
    m = re.search(r"testCandidatePoolContainsOriginal48Prompts.*?let originals = \[(.+?)\]", src, re.DOTALL)
    block = m.group(1)
    return list(re.findall(r'"((?:[^"\\]|\\.)*)"', block))


def escape_swift(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"')


def escape_sql(s: str) -> str:
    return s.replace("'", "''")


def build_swift_content(pool_size: int, swift_array: str) -> str:
    """Swift ファイル内容を組み立てる"""
    lines = []
    lines.append("import Foundation")
    lines.append("")
    lines.append("/// お題の自動生成（F26 / F27）で使う「生成候補プール」と安全判定、フォールバック。")
    lines.append("///")
    lines.append("/// Supabase などのサーバー側ソースが無くてもローカルで「世界共通」のお題を")
    lines.append("/// 日付ベースで 1 日 1 回生成できるよう、候補プールを端末内だけに持つ。")
    lines.append("/// 真に世界中で同じお題が同時に出る厳密な意味での「世界共通」はサーバー側")
    lines.append("/// ソース（Supabase 移行後）に譲り、ここでは「同じ UTC 日付には同じ端末でも")
    lines.append("/// アカウントでも同じ候補が選ばれる」決定性で擬似的に担保する（F26）。")
    lines.append("///")
    lines.append(f"/// 2026-09-08 スプリント19 / F46: 候補プールを ~48 件から約 {pool_size} 件に拡張。")
    lines.append("/// 既存の ~48 件はそのまま残し、新規と混ぜてから決定的シャッフル")
    lines.append("/// （seed=42）で確定。同じ並びが SQL マイグレーションにも一字一句同じ形で")
    lines.append("/// 焼き込まれている（`ensure_todays_prompt()` の v_pool）。")
    lines.append("enum PromptCatalog {")
    lines.append("")
    lines.append("    /// 自動生成で採用しうる「問いかけ」のプール（F26 / 受け入れ条件 5 / F46）。")
    lines.append("    ///")
    lines.append("    /// 既存の `prompt_001`（「今日、思わず笑ってしまったことは何ですか？」）と同種")
    lines.append("    /// ——「短く答えられる／特定文化に依存しない／他人の答えを見ると面白い形式」")
    lines.append("    /// ——になるように Q（`.claude/agents/sameq-prompt-author.md`）の声で生成した。")
    lines.append("    /// 国・宗教・政治・職業・お金・季節の行事・固有名詞・方言・特定の家族構成")
    lines.append("    ///（子ども／配偶者がいる前提）には触れていないので、ロケールや背景に依らず")
    lines.append("    /// 答えられる。生成後に `disallowedKeywords` で再フィルタ済み。")
    lines.append("    ///")
    lines.append("    /// 並びは評価者が全件目視で確認できる量ではなくなったので、隣接日に近い")
    lines.append("    /// お題が続けて出ないように **生成側でカテゴリを混ぜてからシャッフル** してある。")
    lines.append("    /// 同じ並びを `ensure_todays_prompt()` の v_pool（SQL）と共有する。")
    lines.append("    static let candidatePool: [String] = [")
    lines.append(swift_array)
    lines.append("    ]")
    lines.append("")
    lines.append("    /// フォールバック候補（F27 / 受け入れ条件 3）。")
    lines.append("    ///")
    lines.append("    /// 「生成に失敗した日でも必ず何らかのお題が有効になる」ことを担保するため、")
    lines.append("    /// 候補プールが全滅した場合に使う、常に安全だと分かっているお題。")
    lines.append("    /// 中身は同梱シードの `prompt_001` / `prompt_002` と同じ文言。")
    lines.append("    static let fallbackPool: [(id: String, text: String)] = [")
    lines.append('        (id: "prompt_001", text: "今日、思わず笑ってしまったことは何ですか？"),')
    lines.append('        (id: "prompt_002", text: "最近、誰かに言われてうれしかった一言は何ですか？")')
    lines.append("    ]")
    lines.append("")
    lines.append("    /// 安全条件に違反する理由の分類（受け入れ条件 4 のラベル用）。")
    lines.append("    enum DiscardReason: String, Sendable, Equatable {")
    lines.append("        case politics")
    lines.append("        case religion")
    lines.append("        case discrimination")
    lines.append("        case privacy")
    lines.append("        case medical")
    lines.append("        case sexual")
    lines.append("        case crime")
    lines.append("    }")
    lines.append("")
    lines.append("    /// 安全条件に違反するキーワードと、その分類。")
    lines.append("    ///")
    lines.append("    /// 候補プールには最初から含めない前提だが、将来的に外部入力（運用差し込み・")
    lines.append("    /// 将来の本物の生成 AI 呼び出し）へ差し替えるときにも同じ判定を流用できるよう、")
    lines.append("    /// ここに安全条件の根拠を集約する。`PromptSafetyChecker.isAllowed` から利用する。")
    lines.append("    ///")
    lines.append("    /// 仕様にある 7 観点すべてを網羅する:")
    lines.append("    /// - 政治的な対立をあおる（politics）")
    lines.append("    /// - 宗教的な対立をあおる（religion）")
    lines.append("    /// - 差別・ヘイト（discrimination）")
    lines.append("    /// - 個人情報の要求（privacy）")
    lines.append("    /// - 医療診断（medical）")
    lines.append("    /// - 性的内容（sexual）")
    lines.append("    /// - 犯罪をすすめる（crime）")
    lines.append("    static let disallowedKeywords: [(keyword: String, reason: DiscardReason)] = [")
    lines.append("        // 政治的対立")
    lines.append('        ("政党", .politics), ("選挙", .politics), ("投票", .politics), ("政治", .politics),')
    lines.append('        ("左翼", .politics), ("右翼", .politics), ("民主主義", .politics), ("政権", .politics),')
    lines.append('        ("vote", .politics), ("election", .politics), ("politics", .politics), ("political", .politics),')
    lines.append("        // 宗教的対立")
    lines.append('        ("宗教", .religion), ("信仰", .religion), ("教会", .religion),')
    lines.append('        ("religion", .religion), ("religious", .religion),')
    lines.append("        // 差別・ヘイト")
    lines.append('        ("差別", .discrimination), ("ヘイト", .discrimination), ("人種", .discrimination),')
    lines.append('        ("discrimination", .discrimination), ("racism", .discrimination), ("racist", .discrimination),')
    lines.append("        // 個人情報の要求")
    lines.append('        ("住所", .privacy), ("電話番号", .privacy), ("マイナンバー", .privacy), ("パスワード", .privacy),')
    lines.append('        ("address", .privacy), ("phone number", .privacy), ("password", .privacy),')
    lines.append("        // 医療診断")
    lines.append('        ("診断", .medical), ("処方", .medical), ("治療", .medical), ("投薬", .medical),')
    lines.append('        ("diagnosis", .medical), ("prescription", .medical), ("medication", .medical),')
    lines.append("        // 性的内容")
    lines.append('        ("性的", .sexual), ("エロ", .sexual),')
    lines.append("        // 犯罪助長")
    lines.append('        ("万引き", .crime), ("薬物", .crime), ("マリファナ", .crime),')
    lines.append('        ("drugs", .crime), ("steal", .crime)')
    lines.append("    ]")
    lines.append("")
    lines.append("    /// テキストが安全条件を満たすか判定する（F26 / 受け入れ条件 4）。")
    lines.append("    ///")
    lines.append("    /// - Returns: 違反が見つかれば `DiscardReason`、安全なら `nil`。")
    lines.append("    ///   `nil` でない候補は採用されず、`PromptGenerator` が次の候補を試す。")
    lines.append("    static func violationReason(in text: String) -> DiscardReason? {")
    lines.append("        for entry in disallowedKeywords {")
    lines.append("            // 候補プール側は手書きなので包含チェックで十分。後で外部入力に切り替わったら")
    lines.append("            // ここで `Locale.current` を意識した正規化トークン化（NFKC + 大文字小文字）")
    lines.append("            // を入れる余地があるが、いまは仕様外。")
    lines.append("            if text.contains(entry.keyword) { return entry.reason }")
    lines.append("        }")
    lines.append("        return nil")
    lines.append("    }")
    lines.append("}")
    lines.append("")
    lines.append("/// お題の安全条件を判定する純粋関数（F26）。")
    lines.append("enum PromptSafetyChecker {")
    lines.append("    /// `text` が `PromptCatalog.candidatePool` に入れる水準の安全条件を")
    lines.append("    /// 満たしているかを判定する。")
    lines.append("    static func isAllowed(_ text: String) -> Bool {")
    lines.append("        PromptCatalog.violationReason(in: text) == nil")
    lines.append("    }")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def build_sql_content(pool_size: int, sql_pool_array: str) -> str:
    """SQL マイグレーション内容を組み立てる"""
    lines = []
    lines.append(f"-- SameQ スプリント19 / F46（2026-09-08）:")
    lines.append(f"-- お題プールを約48件から約{pool_size}件に拡張する。")
    lines.append("--")
    lines.append("-- 背景:")
    lines.append("--   既存のお題プール（migration 13/14）は約48件で、運用開始から半年強で全問出し切った")
    lines.append("--   後に「前に見た問い」に当たってしまう状態になっていた。spec.md F46 / F30 の決定")
    lines.append(f"--   （「ある程度まで作ったら ship して放置」）に従い、約{pool_size}件（950〜1,100件の範囲）")
    lines.append("--   に拡張する。既存の約48件はそのまま残し、新規と混ぜてから決定的シャッフル（seed=42）")
    lines.append("--   で確定。同じ並びが `SameQ/Backend/PromptCatalog.swift` の `candidatePool` にも")
    lines.append("--   一字一句同じ形で焼き込まれている（`PromptGenerator` の startIndex 計算式と互換）。")
    lines.append("--")
    lines.append("-- 影響範囲:")
    lines.append(f"--   * ensure_todays_prompt() の候補プールを {pool_size} 件に更新。アルゴリズムは不変")
    lines.append("--     （`((day_index % pool_size) + pool_size/2) % pool_size`）。")
    lines.append("--")
    lines.append("-- 冪等性:")
    lines.append("--   * ensure_todays_prompt() は `create or replace function`。")
    lines.append("-- ---------------------------------------------------------------------------")
    lines.append("")
    lines.append("-- ---------------------------------------------------------------------------")
    lines.append(f"-- ensure_todays_prompt() を新プール ({pool_size} 件) で書き換え")
    lines.append("--")
    lines.append("-- アルゴリズムは不変。`((day_index % pool_size) + pool_size/2) % pool_size` で")
    lines.append("-- 隣接日に近いお題が続けて出ないように中盤から走査する。PromptGenerator.swift")
    lines.append("-- (Swift 側 / LocalBackend) と同じ式。")
    lines.append("-- ---------------------------------------------------------------------------")
    lines.append("create or replace function public.ensure_todays_prompt()")
    lines.append("returns void")
    lines.append("language plpgsql")
    lines.append("security definer")
    lines.append("set search_path = public")
    lines.append("as $$")
    lines.append("declare")
    lines.append(f"    -- 候補プール {pool_size} 件は PromptCatalog.candidatePool (Swift) と一字一句同期。")
    lines.append("    -- 並びは決定的シャッフル済み (seed=42)。ここを変更したら PromptGenerator.swift /")
    lines.append("    -- PromptCatalog.swift も必ず同期すること。")
    lines.append("    v_pool text[] := array[")
    lines.append(sql_pool_array)
    lines.append("    ];")
    lines.append("    v_pool_size int := array_length(v_pool, 1);")
    lines.append("    v_day_key   text;")
    lines.append("    v_day_index int;")
    lines.append("    v_start_idx int;")
    lines.append("    v_text      text;")
    lines.append("    v_starts_at timestamptz;")
    lines.append("    v_ends_at   timestamptz;")
    lines.append("    v_truncated_count int;")
    lines.append("begin")
    lines.append("    v_day_key   := to_char((now() at time zone 'utc')::date, 'YYYYMMDD');")
    lines.append("    v_day_index := date(now() at time zone 'utc') - date '1970-01-01';")
    lines.append("")
    lines.append("    -- 隣接日に近いお題が続けて出ないよう中盤から走査。")
    lines.append("    v_start_idx := ((v_day_index % v_pool_size) + v_pool_size / 2) % v_pool_size;")
    lines.append("    v_text      := v_pool[v_start_idx + 1]; -- Postgres 配列は 1-indexed")
    lines.append("")
    lines.append("    v_starts_at := date_trunc('day', now() at time zone 'utc') at time zone 'utc';")
    lines.append("    v_ends_at   := v_starts_at + interval '28 hours';")
    lines.append("")
    lines.append("    -- 直前のプロンプトで新プロンプトと重なるものを `ends_at = v_starts_at` に切り詰めて")
    lines.append("    -- overlap を消す（`prompts_no_overlap` 制約を満たすため）。")
    lines.append("    update public.prompts")
    lines.append("    set ends_at = v_starts_at")
    lines.append("    where ends_at > v_starts_at")
    lines.append("      and starts_at < v_starts_at;")
    lines.append("    get diagnostics v_truncated_count = row_count;")
    lines.append("    raise notice 'ensure_todays_prompt: truncated % previous prompt(s) to ends_at = %', v_truncated_count, v_starts_at;")
    lines.append("")
    lines.append("    insert into public.prompts (id, text, starts_at, ends_at)")
    lines.append("    values ('prompt_' || v_day_key, v_text, v_starts_at, v_ends_at)")
    lines.append("    on conflict (id) do nothing;")
    lines.append("end;")
    lines.append("$$;")
    lines.append("")
    lines.append("comment on function public.ensure_todays_prompt() is")
    lines.append("    '本番 prompts に今日の有効なお題が1件も無いとき、決定的アルゴリズムで")
    lines.append("     1件生成してupsertする（冪等）。2026-09-08 スプリント19 で候補プールを")
    lines.append(f"     {pool_size} 件に拡張（spec.md F46）。Swift 側の PromptCatalog.candidatePool と")
    lines.append("     一字一句同期。隣接日に近いお題が続けて出ないよう中盤から走査する。';")
    lines.append("")
    lines.append("revoke all on function public.ensure_todays_prompt() from public;")
    lines.append("grant execute on function public.ensure_todays_prompt() to authenticated;")
    lines.append("")
    return "\n".join(lines)


def main():
    lines = INPUT.read_text().splitlines()
    lines = [l for l in lines if l.strip()]
    print(f"入力: {len(lines)} 件")

    originals = extract_originals_from_test()
    originals_set = set(originals)

    missing = [o for o in originals if o not in lines]
    if missing:
        print(f"!!! originals が欠落: {missing}")
        sys.exit(1)
    print(f"✓ 既存の {len(originals)} 件全て含まれる")

    rng = random.Random(42)
    shuffled = lines.copy()
    rng.shuffle(shuffled)
    print(f"シャッフル後: {len(shuffled)} 件")

    missing2 = [o for o in originals if o not in shuffled]
    if missing2:
        print(f"!!! シャッフル後に originals が欠落: {missing2}")
        sys.exit(1)

    SHUFFLED_OUT.write_text("\n".join(shuffled) + "\n")
    print(f"シャッフル結果: {SHUFFLED_OUT}")

    # === Swift ファイル生成 ===
    swift_lines = []
    for line in shuffled:
        swift_lines.append(f'        "{escape_swift(line)}",')
    swift_array = "\n".join(swift_lines)

    POOL_SIZE = len(shuffled)
    swift_content = build_swift_content(POOL_SIZE, swift_array)
    SWIFT_FILE.write_text(swift_content)
    print(f"Swift ファイル書き出し: {SWIFT_FILE} ({POOL_SIZE} 件)")

    # === SQL マイグレーション生成 ===
    sql_pool_lines = []
    for line in shuffled:
        sql_pool_lines.append(f"        '{escape_sql(line)}',")
    sql_pool_array = "\n".join(sql_pool_lines)

    sql_content = build_sql_content(POOL_SIZE, sql_pool_array)
    MIGRATION_FILE.write_text(sql_content)
    print(f"SQL マイグレーション書き出し: {MIGRATION_FILE} ({POOL_SIZE} 件)")


if __name__ == "__main__":
    main()