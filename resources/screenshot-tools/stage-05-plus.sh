#!/usr/bin/env bash
# stage-05-plus.sh
# Plus サブスク画面（PlusView）を撮影する
# 引数: $1=udid $2=appleLanguage $3=appleLocale $4=appPath $5=outDir
set -euo pipefail

UDID="${1:?udid required}"
APPLE_LANGUAGE="${2:?appleLanguage required}"
APPLE_LOCALE="${3:?appleLocale required}"
APP_PATH="${4:?appPath required}"
OUT_DIR="${5:?outDir required}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
VTAP="$HOME/.agents/skills/ios-screenshot-shoot/scripts/vtap.sh"

mkdir -p "$OUT_DIR"
SHOT="$OUT_DIR/05-plus.png"

xcrun simctl bootstatus "$UDID" -b 2>/dev/null || true
xcrun simctl terminate "$UDID" com.nakakei6439.SameQ 2>/dev/null || true
sleep 1
xcrun simctl launch "$UDID" com.nakakei6439.SameQ >/dev/null 2>&1
sleep 10

# TODO(init 後): メニュー → Plus を開く
# FakePlus を立てているため、PlusView が「加入済み」表示になる可能性あり。
# 撮影時に「加入検討中」の画面を見せるには -SameQFakePlus を外す or
# 開発者モードで「常に無料」に切替（Menu の隠し8連打）の操作が必要。

xcrun simctl io "$UDID" screenshot "$SHOT"
echo "[stage-05-plus] wrote $SHOT"
