#!/usr/bin/env bash
# stage-03-menu.sh
# メニュー（ハンバーガー）撮影
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
SHOT="$OUT_DIR/03-menu.png"

xcrun simctl bootstatus "$UDID" -b 2>/dev/null || true
xcrun simctl terminate "$UDID" com.nakakei6439.SameQ 2>/dev/null || true
sleep 1
xcrun simctl launch "$UDID" com.nakakei6439.SameQ >/dev/null 2>&1
sleep 10

# TODO(init 後): ヘッダーのハンバーガー座標を vtap.sh 経由で叩く

xcrun simctl io "$UDID" screenshot "$SHOT"
echo "[stage-03-menu] wrote $SHOT"
