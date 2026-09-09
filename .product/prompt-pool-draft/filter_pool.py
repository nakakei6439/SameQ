#!/usr/bin/env python3
"""Sprint19 / F46: お題プールから壊れたお題を除去する。

入力: .product/prompt-pool-draft/final-pool.txt (1,083 件)
出力: .product/prompt-pool-draft/filtered-pool.txt

戦略:
1. テストファイルから originals を抽出 (48 件) — これらは必ず残す
2. final-pool.txt を読み、originals との差分 (near-match) をタイポ修正
3. 機械量産の壊れたお題 (好きなった、寸法系、二重助詞) を除去
4. 出力は 950-1100 件に収まるよう、必要なら追加
"""

import re
import sys
from pathlib import Path

PROJECT_ROOT = Path("/Users/nakagawakeita/Products/iOSApp/SameQ")
INPUT = PROJECT_ROOT / ".product/prompt-pool-draft/final-pool.txt"
OUTPUT = PROJECT_ROOT / ".product/prompt-pool-draft/filtered-pool.txt"
LOG = PROJECT_ROOT / ".product/prompt-pool-draft/filter-log.txt"
TEST_FILE = PROJECT_ROOT / "SameQTests/PromptGenerationTests.swift"


def extract_originals_from_test():
    """テストファイルから originals を抽出"""
    src = TEST_FILE.read_text()
    # find the array
    m = re.search(r"testCandidatePoolContainsOriginal48Prompts.*?let originals = \[(.+?)\]", src, re.DOTALL)
    if not m:
        raise RuntimeError("originals array not found in test file")
    block = m.group(1)
    # Extract quoted strings
    return re.findall(r'"((?:[^"\\]|\\.)*)"', block)


def main():
    originals = extract_originals_from_test()
    originals_set = set(originals)
    print(f"テストから抽出した originals: {len(originals)} 件")

    lines = INPUT.read_text().splitlines()
    lines = [l for l in lines if l.strip()]
    print(f"入力: {len(lines)} 件")

    # original に含まれる各テキストを pool から見つける。見つからないものは
    # 「候補が似ている」(1 文字違い) 行を探して typo fix マップを作る
    typo_fixes = {}  # pool_str -> fixed_str
    missing_after_typo_fix = []
    for orig in originals:
        if orig in lines:
            continue
        # 候補: pool の各行で、長さが ±2 以内 + 先頭5文字が一致
        candidates = []
        for line in lines:
            if abs(len(line) - len(orig)) <= 2:
                if line[:5] == orig[:5]:
                    candidates.append(line)
        # typo fix: 一番近いものを採用
        if len(candidates) == 1:
            typo_fixes[candidates[0]] = orig
        elif len(candidates) > 1:
            # Choose the closest by edit distance
            def edit_dist(a, b):
                if len(a) < len(b):
                    a, b = b, a
                prev = list(range(len(b) + 1))
                for i, ca in enumerate(a):
                    cur = [i + 1]
                    for j, cb in enumerate(b):
                        cur.append(min(cur[-1] + 1, prev[j + 1] + 1, prev[j] + (ca != cb)))
                    prev = cur
                return prev[-1]
            best = min(candidates, key=lambda l: edit_dist(l, orig))
            typo_fixes[best] = orig
        else:
            missing_after_typo_fix.append(orig)

    print(f"自動検出 typo fix 候補: {len(typo_fixes)} 件")
    if missing_after_typo_fix:
        print(f"!!! typo fix 後も見つからない originals:")
        for m in missing_after_typo_fix:
            print(f"  - {m}")
        # show first 10 chars
        sys.exit(1)

    # Apply typo fixes
    lines_after_typo = []
    typo_count = 0
    for line in lines:
        if line in typo_fixes:
            lines_after_typo.append(typo_fixes[line])
            typo_count += 1
        else:
            lines_after_typo.append(line)
    print(f"タイポ修正適用: {typo_count} 件")
    if typo_count > 0:
        for k, v in typo_fixes.items():
            print(f"  '{k}' -> '{v}'")
    lines = lines_after_typo

    # 再度 originals check
    still_missing = [o for o in originals if o not in lines]
    if still_missing:
        print(f"!!! タイポ修正後も見つからない originals: {still_missing}")
        sys.exit(1)
    print(f"✓ タイポ修正後、48 originals 全て pool に含まれる")

    # ここからフィルタリング
    kept = []
    removed_reasons = {
        "好きなった": 0,
        "寸法系": 0,
        "二重助詞": 0,
        "禁則キーワード": 0,
        "機械量産_属性問い": 0,
        "今日の機嫌_変種": 0,
        "体の哪里": 0,
        "今日_誰かの前で_量産": 0,
        "誰にも_小さな_X_を_量産": 0,
        "機械量産_微妙": 0,
        "二重問い": 0,
    }

    log_lines = []

    DIMENSION_WORDS = [
        "形", "薄さ", "厚さ", "大きさ", "小ささ", "量", "数", "濃さ", "長さ",
        "重さ", "高さ", "速さ", "湿度", "温度", "甘さ", "塩っぱさ", "辛さ",
        "苦さ", "酸っぱさ", "刺激", "感触", "香り", "色", "音", "光",
        "期待", "驚き", "余韻", "記憶", "発見", "タイミング", "組み合わせ",
        "出会いは", "満足", "順番", "目覚め", "眠り", "呼吸",
        "食べ終わるタイミング", "飲み終わるタイミング",
        "食べる量", "飲む量", "食べる速さ", "飲む速さ", "食べる組み合わせ",
        "飲む組み合わせ", "食べ物の色", "記憶のよみがえり",
    ]

    FORBIDDEN_KEYWORDS = [
        "日本", "中国", "韓国", "アメリカ", "フランス", "イタリア", "ドイツ",
        "ロシア", "ブラジル", "インド", "イギリス",
        "宗教", "教会", "神様", "神社", "寺",
        "政党", "選挙", "投票", "政治", "議員", "大統領", "首相",
        "面接", "就職", "上司", "部下", "同僚", "給料", "ボーナス",
        "お正月", "クリスマス", "バレンタイン", "ハロウィン", "花見", "お盆",
        "忘年会", "新年会", "七夕", "節分", "端午", "ひな祭り",
        "ボチボチ", "ええねん", "知らんけど", "なんでやねん",
        "Spotify", "Apple Music", "Google", "Netflix", "Amazon",
    ]

    # 機械量産された「ここ数日で一番好きなった」
    MECHANICAL_PATTERNS = [
        r"^ここ数日で一番好きなった",
        r"^最近、好きなった",
    ]

    # 機械量産された属性問い
    ATTR_PURPOSELESS_NAMES = [
        "自由さ", "柔らかさ", "硬さ", "弱さ", "強さ", "厳しさ", "寛容さ",
        "不完全さ", "完全さ", "静けさ", "にぎやかさ", "明るさ", "暗さ",
        "大きさ", "小ささ", "速さ",
        "甘さ", "苦さ", "辛さ", "塩っぱさ", "酸っぱさ", "薄さ", "厚さ",
        "粘り強さ", "素直さ", "静かさ", "穏やかさ",
        "リズム", "テンポ", "直感",
        "歩く速さ", "話す速さ", "食べる速さ", "飲む速さ", "考える速さ",
        "続けるタイミング", "やめるタイミング",
        "決めるタイミング", "迷うタイミング", "怒るタイミング", "笑うタイミング",
        "泣くタイミング", "疑うタイミング", "信じるタイミング", "頼るタイミング",
        "頼られるタイミング", "許すタイミング", "始めるタイミング", "止まるタイミング",
        "不自由さ", "目覚め", "体調", "気分",
        "厳しさ", "寛容さ", "粘り強さ", "完全さ", "不完全さ",
        "新たな一面", "意外な面",
        "大事な瞬間", "大切な瞬間",
        "大事な場所", "大事な考え",
        "大事にしている瞬間", "大事にしている朝", "大事にしている夜", "大事にしている夕方",
        "大事にしている夜明け", "大事にしている日没", "大事にしている葉",
        "大事にしている根", "大事にしている火", "大事にしている水",
        "大事にしている光", "大事にしている風", "大事にしている土", "大事にしている種",
        "大事にしている緑", "大事にしている静けさ", "大事にしているにぎやかさ",
        "大事にしているリズム", "大事にしている明るさ", "大事にしている暗さ",
        "大事にしている花", "大事にしている木",
        "大事にしている叶", "大事にしている影", "大事にしている言葉遣い",
        "大事にしている考え方", "大事にしている感覚",
        "大事な考え方", "大事な感覚",
    ]

    DOUBLE_PARTICLE_PATTERNS = [
        r"のの",
        r"にに",
        r"はは",
        r"がが",
        r"をを",
        r"をが",
        r"がを",
    ]

    for line in lines:
        if line in originals_set:
            kept.append(line)
            continue

        # 「好きなった」を含む
        if "好きなった" in line:
            removed_reasons["好きなった"] += 1
            log_lines.append(f"REMOVE [好きなった]: {line}")
            continue

        # 機械量産パターン
        is_mechanical = False
        for pat in MECHANICAL_PATTERNS:
            if re.match(pat, line):
                removed_reasons["好きなった"] += 1
                log_lines.append(f"REMOVE [機械量産_最近最上級]: {line}")
                is_mechanical = True
                break
        if is_mechanical:
            continue

        # 寸法系「◯◯の{形/薄さ/...}は？」
        if line.endswith("は？"):
            is_dim = False
            for dim in DIMENSION_WORDS:
                if f"の{dim}は？" in line:
                    is_dim = True
                    break
            if is_dim:
                removed_reasons["寸法系"] += 1
                log_lines.append(f"REMOVE [寸法系]: {line}")
                continue

        # 機械量産された属性問い
        if line.startswith("この一年で、はじめて気づいた自分の"):
            if line.endswith("は？"):
                inner = line[len("この一年で、はじめて気づいた自分の"):-len("は？")]
                if any(kw in inner for kw in ["大事にしている", "大事に", "許せない", "好き嫌い", "嫌いなところ", "好きなところ", "新たな一面", "意外な面"]):
                    pass  # keep
                else:
                    is_attr = False
                    for attr in ATTR_PURPOSELESS_NAMES:
                        if inner == attr or inner.endswith(attr) or inner.startswith(attr):
                            is_attr = True
                            break
                    if is_attr:
                        removed_reasons["機械量産_属性問い"] += 1
                        log_lines.append(f"REMOVE [機械量産_属性問い]: {line}")
                        continue

        # 二重助詞
        has_dp = False
        for pat in DOUBLE_PARTICLE_PATTERNS:
            if re.search(pat, line):
                has_dp = True
                break
        if has_dp:
            removed_reasons["二重助詞"] += 1
            log_lines.append(f"REMOVE [二重助詞]: {line}")
            continue

        # 禁則キーワード
        has_fk = False
        for kw in FORBIDDEN_KEYWORDS:
            if kw in line:
                has_fk = True
                break
        if has_fk:
            removed_reasons["禁則キーワード"] += 1
            log_lines.append(f"REMOVE [禁則キーワード]: {line}")
            continue

        # 今日の機嫌の変種
        if line.startswith("今日のあなた") and ("一番左右" in line) and ("みっつ" in line or "ふたつ" in line or "ひとつ" in line):
            removed_reasons["今日の機嫌_変種"] += 1
            log_lines.append(f"REMOVE [今日の機嫌_変種]: {line}")
            continue

        # 「体の哪里」(中国語の混在)
        if "体の哪里" in line:
            removed_reasons["体の哪里"] += 1
            log_lines.append(f"REMOVE [体の哪里]: {line}")
            continue

        # 「今日、誰かの前で「...」と言えた瞬間は？」の機械量産
        if "今日、誰かの前で「" in line and "と言えた瞬間は？" in line:
            removed_reasons["今日_誰かの前で_量産"] += 1
            log_lines.append(f"REMOVE [今日_誰かの前で_量産]: {line}")
            continue

        # 「誰にも話していない小さな{X}を、{N}つだけ言葉にしてみてください。」の機械量産
        # (元の 48 で「願い」がひとつだけあるが、他は量産)
        if line.startswith("誰にも話していない小さな"):
            # 末尾が「教えてください。」または「言葉にしてみてください。」
            if "言葉にしてみてください。" in line:
                # 数を聞くもの (ひとつ/ふたつ/みっつ) は量産
                if "、ひとつだけ言葉にしてみてください。" in line or "、ふたつだけ言葉にしてみてください。" in line or "、みっつだけ言葉にしてみてください。" in line:
                    # 既存の原文「誰にも話していない小さな願いを、ひとつだけ言葉にしてみてください。」は除外
                    if line in originals_set:
                        kept.append(line)
                        continue
                    removed_reasons["誰にも_小さな_X_を_量産"] += 1
                    log_lines.append(f"REMOVE [誰にも_小さな_X_を_量産]: {line}")
                    continue
                elif "教えてください。" in line:
                    # 「「なんでもない」と流したけれど本当は少し気になっていることを教えてください。」は既存
                    if line in originals_set:
                        kept.append(line)
                        continue
                    # 「誰にも話していないけれど本当は少し気になっていることを、ひとつだけ教えてください。」系も量産
                    if "、ひとつだけ教えてください" in line or "、ふたつ教えてください" in line or "、みっつ教えてください" in line:
                        removed_reasons["誰にも_小さな_X_を_量産"] += 1
                        log_lines.append(f"REMOVE [誰にも_小さな_X_を_量産]: {line}")
                        continue

        # 二重問い (質問が 2 つ) を検出
        if line.count("？") > 1:
            # 通常は「〜は？〜は？」のような形
            parts = re.split(r'[、，]', line)
            if len(parts) > 1 and any("？" in p for p in parts[:-1]):
                # コンマで区切られて複数の ? がある
                removed_reasons["二重問い"] += 1
                log_lines.append(f"REMOVE [二重問い]: {line}")
                continue

        # それ以外は残す
        kept.append(line)

    print(f"\n出力: {len(kept)} 件")
    print("削除内訳:")
    for k, v in removed_reasons.items():
        print(f"  {k}: {v}")

    missing = [o for o in originals if o not in kept]
    if missing:
        print(f"!!! フィルタ後に失われた originals: {missing}")
        sys.exit(1)
    else:
        print(f"✓ 既存の {len(originals)} 件は全て残存")

    OUTPUT.write_text("\n".join(kept) + "\n")
    LOG.write_text("\n".join(log_lines) + "\n")
    print(f"\n書き出し: {OUTPUT}")
    print(f"ログ: {LOG}")


if __name__ == "__main__":
    main()