#!/usr/bin/env python3
"""Sprint19 / F46: 語幹重複をさらに減らす (各語幹グループ最大 N 件)。

入力: .product/prompt-pool-draft/deduped-pool.txt
出力: .product/prompt-pool-draft/deduped-pool.txt (上書き)
"""

import re
import sys
from pathlib import Path

PROJECT_ROOT = Path("/Users/nakagawakeita/Products/iOSApp/SameQ")
INPUT = PROJECT_ROOT / ".product/prompt-pool-draft/deduped-pool.txt"
OUTPUT = PROJECT_ROOT / ".product/prompt-pool-draft/deduped-pool.txt"  # 上書き
LOG = PROJECT_ROOT / ".product/prompt-pool-draft/dedup2-log.txt"
TEST_FILE = PROJECT_ROOT / "SameQTests/PromptGenerationTests.swift"


def extract_originals_from_test():
    src = TEST_FILE.read_text()
    m = re.search(r"testCandidatePoolContainsOriginal48Prompts.*?let originals = \[(.+?)\]", src, re.DOTALL)
    block = m.group(1)
    return set(re.findall(r'"((?:[^"\\]|\\.)*)"', block))


def stem(line: str) -> str:
    """語幹の抽出: 形容句、数詞、動詞句を除去"""
    s = line
    # 数詞
    s = re.sub(r"(ひとつ|ふたつ|みっつ)(だけ)?", "X", s)
    s = re.sub(r"、ひとつ", "X", s)
    s = re.sub(r"をふたつ", "をY", s)
    s = re.sub(r"をみっつ", "をZ", s)
    s = re.sub(r"をひとつ", "をW", s)
    # 形容句
    s = re.sub(r"「なんでもない」と流したけれど", "", s)
    s = re.sub(r"誰にも言っていないけれど", "", s)
    s = re.sub(r"誰にも話していないけれど", "", s)
    s = re.sub(r"誰にも言っていない小さな", "", s)
    s = re.sub(r"誰にも話していない小さな", "", s)
    s = re.sub(r"、ちょっと|、すこし|、少し|、ほんの少し|、ほんの少しだけ", "", s)
    s = re.sub(r"ちょっと|すこし|少し|ほんの少し", "", s)
    s = re.sub(r"、ふたつ|、みっつ|、ひとつ", "", s)
    s = re.sub(r"本当は少し気に(なっている|している)", "REAL", s)
    # 「そっと + 動詞」系
    s = re.sub(r"、そっと[ア-ンー]+[むみる]?[ア-ンー]*", "GENTLY", s)
    s = re.sub(r"、[ア-ンー]{2,5}してみる[？]?", "ACT", s)
    s = re.sub(r"、[ア-ンー]{2,5}してみるとしたら[？]?", "ACT", s)
    s = re.sub(r"、[ア-ンー]{2,5}してみるなら[？]?", "ACT", s)
    # 末尾動詞句
    s = re.sub(r"教えてください[。]?", "TELL", s)
    s = re.sub(r"言葉にしてみてください[。]?", "SAY", s)
    s = re.sub(r"言葉にしてみると?", "SAY2", s)
    s = re.sub(r"、声に出すと?", "VOICE", s)
    s = re.sub(r"、紙に書くと?", "PAPER", s)
    s = re.sub(r"、絵にすると?", "PICTURE", s)
    s = re.sub(r"、誰かに話すと?[？]?", "TELLME", s)
    s = re.sub(r"、手放してみるなら[？]?", "LETGO", s)
    s = re.sub(r"、手放すと?[？]?", "LETGO", s)
    s = re.sub(r"、眺めてみるとしたら[？]?", "WATCH", s)
    s = re.sub(r"、眺めると?[？]?", "WATCH", s)
    s = re.sub(r"、抱えてみるとしたら[？]?", "HOLD", s)
    s = re.sub(r"、抱えると?[？]?", "HOLD", s)
    s = re.sub(r"、形にすると?", "FORM", s)
    s = re.sub(r"、形にするとしたら[？]?", "FORM", s)
    s = re.sub(r"、形にする[？]?", "FORM", s)
    # 質問の末尾
    s = re.sub(r"はありますか[？]?", "Q1", s)
    s = re.sub(r"はありましたか[？]?", "Q1", s)
    s = re.sub(r"としたら[？]?", "Q2", s)
    s = re.sub(r"するなら[？]?", "Q3", s)
    s = re.sub(r"してみるとしたら[？]?", "Q4", s)
    s = re.sub(r"するとしたら[？]?", "Q4", s)
    s = re.sub(r"してみます[ねか]?[？]?", "Q4", s)
    s = re.sub(r"だろうか[？]?", "Q5", s)
    # 句読点
    s = s.replace("？", "").replace("?", "").replace("。", "").replace(",", "")
    s = re.sub(r"\s+", "", s)
    return s


def main():
    originals = extract_originals_from_test()
    lines = INPUT.read_text().splitlines()
    lines = [l for l in lines if l.strip()]
    print(f"入力: {len(lines)} 件")

    # グループ化
    groups = {}
    for line in lines:
        groups.setdefault(stem(line), []).append(line)

    print(f"全グループ数: {len(groups)}")

    # 各グループの最大件数
    MAX_PER_STEM = {
        "体のどこ": 25,  # body questions — keep ~25
        "好きなX": 30,  # single-thing "いま、好きな◯◯をひとつだけ挙げるとしたら" questions
        "大事にしているX": 30,  # important thing
        "誰かに届けたいもの": 20,
        "もし一日だけX": 50,  # もし一日だけ◯◯ pattern
        "この一年ではじめてX": 30,  # この一年で、はじめて...
        # default: 5
    }
    DEFAULT_MAX = 5

    def get_max_for_stem(stem_str):
        for key, val in MAX_PER_STEM.items():
            if key in stem_str:
                return val
        return DEFAULT_MAX

    kept = []
    removed = []
    for s, variants in groups.items():
        max_n = get_max_for_stem(s)
        if len(variants) <= max_n:
            kept.extend(variants)
            continue
        # original を優先、次に短い順、残りは削除
        originals_v = [v for v in variants if v in originals]
        others = [v for v in variants if v not in originals]
        others_sorted = sorted(others, key=len)
        candidates = originals_v + others_sorted
        for v in candidates[:max_n]:
            kept.append(v)
        for v in candidates[max_n:]:
            removed.append((v, f"over-cap (max={max_n}, stem={s[:60]})"))

    print(f"出力: {len(kept)} 件 (除去: {len(removed)} 件)")

    missing = [o for o in originals if o not in kept]
    if missing:
        print(f"!!! 失われた originals: {missing}")
        sys.exit(1)

    log_lines = [f"REMOVE [{reason}]" for line, reason in removed]

    OUTPUT.write_text("\n".join(kept) + "\n")
    LOG.write_text("\n".join(log_lines) + "\n")
    print(f"書き出し: {OUTPUT}")

    # 統計
    print("\nStem stats (top 20 by count):")
    for s, v in sorted(groups.items(), key=lambda x: -len(x[1]))[:20]:
        print(f"  ({len(v)}) stem={s[:60]}")


if __name__ == "__main__":
    main()