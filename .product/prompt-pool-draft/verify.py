#!/usr/bin/env python3
"""Swift ↔ SQL の byte-exact 一致を検証する。"""

import re
import sys
from pathlib import Path

PROJECT_ROOT = Path("/Users/nakagawakeita/Products/iOSApp/SameQ")
SWIFT_FILE = PROJECT_ROOT / "SameQ/Backend/PromptCatalog.swift"
SQL_FILE = PROJECT_ROOT / "supabase/migrations/20260908000001_sprint19_prompt_pool_expansion.sql"
TEST_FILE = PROJECT_ROOT / "SameQTests/PromptGenerationTests.swift"


def extract_originals_from_test():
    src = TEST_FILE.read_text()
    m = re.search(r"testCandidatePoolContainsOriginal48Prompts.*?let originals = \[(.+?)\]", src, re.DOTALL)
    block = m.group(1)
    return list(re.findall(r'"((?:[^"\\]|\\.)*)"', block))


def extract_swift_pool(path: Path) -> list:
    src = path.read_text()
    m = re.search(r"static let candidatePool: \[String\] = \[(.*?)\]", src, re.DOTALL)
    if not m:
        raise RuntimeError("candidatePool not found")
    body = m.group(1)
    return re.findall(r'"((?:[^"\\]|\\.)*)"', body)


def extract_sql_pool(path: Path) -> list:
    src = path.read_text()
    m = re.search(r"v_pool text\[\] := array\[(.*?)\];", src, re.DOTALL)
    if not m:
        raise RuntimeError("v_pool not found")
    body = m.group(1)
    return re.findall(r"'((?:[^']|'')*)'", body)


def main():
    originals = extract_originals_from_test()
    print(f"originals (test): {len(originals)} 件")

    swift_pool = extract_swift_pool(SWIFT_FILE)
    sql_pool = extract_sql_pool(SQL_FILE)
    print(f"Swift candidatePool: {len(swift_pool)} 件")
    print(f"SQL v_pool: {len(sql_pool)} 件")

    if len(swift_pool) != len(sql_pool):
        print(f"!!! 件数不一致")
        sys.exit(1)

    if swift_pool != sql_pool:
        print(f"!!! 内容不一致")
        for i, (s, q) in enumerate(zip(swift_pool, sql_pool)):
            if s != q:
                print(f"  差分 at {i}:")
                print(f"    swift: {s}")
                print(f"    sql:   {q}")
                if i > 5:
                    break
        sys.exit(1)

    print(f"✓ Swift ↔ SQL byte-exact 一致 ({len(swift_pool)} 件)")

    # originals check
    missing_swift = [o for o in originals if o not in swift_pool]
    if missing_swift:
        print(f"!!! Swift に originals 欠落: {len(missing_swift)} 件")
        sys.exit(1)
    missing_sql = [o for o in originals if o not in sql_pool]
    if missing_sql:
        print(f"!!! SQL に originals 欠落: {len(missing_sql)} 件")
        sys.exit(1)
    print(f"✓ 既存の {len(originals)} 件全て含まれる")

    # 範囲チェック
    if not (950 <= len(swift_pool) <= 1100):
        print(f"!!! 範囲外: {len(swift_pool)} (950〜1100 期待)")
        sys.exit(1)
    print(f"✓ 範囲 OK (950〜1100): {len(swift_pool)}")

    # 重複チェック
    if len(set(swift_pool)) != len(swift_pool):
        print(f"!!! 重複あり: ユニーク {len(set(swift_pool))} / 全体 {len(swift_pool)}")
        sys.exit(1)
    print(f"✓ 重複なし")


if __name__ == "__main__":
    main()