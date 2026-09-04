#!/usr/bin/env bash
# stage-01-today.sh
# 起動直後の TodayPromptView（オンボーディングスキップ済み）を撮影する
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
SHOT="$OUT_DIR/01-today.png"

# 専用 sim を前面化
xcrun simctl bootstatus "$UDID" -b 2>/dev/null || true

# アプリを再起動（言語は init で simctl 設定済み。launchArgs は config 経由）
xcrun simctl terminate "$UDID" com.nakakei6439.SameQ 2>/dev/null || true
sleep 1
xcrun simctl launch "$UDID" com.nakakei6439.SameQ >/dev/null 2>&1
sleep 10

# 起動直後の TodayPromptView を撮影
xcrun simctl io "$UDID" screenshot "$SHOT"
echo "[stage-01-today] wrote $SHOT"
