#!/usr/bin/env bash
# shoot-locale.sh — SameQ の 5 カットを 1 ロケール分撮影する（maestro を介さず simctl 直）
# 使い方: shoot-locale.sh <locale> <mode>
#   locale: ja | en
#   mode:   all | timeline | main
#     all      : timeline (02) + main (01/03/04/05) を順に
#     timeline : answered state.json + 02-timeline のみ
#     main     : unanswered state.json + 01, 03, 04, 05
set -euo pipefail

UDID="${SHOOT_UDID:-D3F23383-F87A-46FD-9A46-A23ED8DFF85E}"
LOCALE="${1:?locale required (ja|en)}"
MODE="${2:-all}"
SHOOT_ROOT="/Users/nakagawakeita/Products/iOSApp/SameQ"
OUT_BASE="/Users/nakagawakeita/Desktop/SameQ-screenshots-2026-08-30/raw"
APP_CONTAINER=$(xcrun simctl get_app_container "$UDID" com.nakakei6439.SameQ data)
STATE_JSON="$APP_CONTAINER/Library/Application Support/SameQ/state.json"

shot() {  # shot <locale> <filename>
  local filename="$1"
  local out_path="$OUT_BASE/$LOCALE/$filename"
  mkdir -p "$(dirname "$out_path")"
  xcrun simctl io booted screenshot "$out_path"
  echo "  → shot: $out_path ($(stat -f%z "$out_path") bytes)"
}

set_language() {
  case "$LOCALE" in
    ja) LANG="ja_JP" ;;
    en) LANG="en_US" ;;
  esac
  echo "[$LOCALE] 言語設定: AppleLanguages=$LOCALE, AppleLocale=$LANG"
  xcrun simctl spawn "$UDID" defaults write -g AppleLanguages -array "$LOCALE"
  xcrun simctl spawn "$UDID" defaults write -g AppleLocale "$LANG"
  # SpringBoard 再起動
  xcrun simctl shutdown "$UDID" 2>/dev/null || true
  sleep 2
  xcrun simctl boot "$UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$UDID" -b 30 2>/dev/null || true
  sleep 3
}

# 言語切替
set_language

# timeline 撮影 (answered state.json を使う)
if [ "$MODE" = all ] || [ "$MODE" = timeline ]; then
  echo "[$LOCALE] answered state.json を配置（02-timeline 撮影）"
  cp "$SHOOT_ROOT/resources/screenshot-tools/state-answered-${LOCALE}.json" "$STATE_JSON"
  xcrun simctl terminate "$UDID" com.nakakei6439.SameQ 2>/dev/null || true
  sleep 1
  xcrun simctl launch "$UDID" com.nakakei6439.SameQ -SameQUseLocalBackend >/dev/null
  sleep 8
  shot "02-timeline.png"
  xcrun simctl terminate "$UDID" com.nakakei6439.SameQ 2>/dev/null || true
fi

# main 撮影 (unanswered state.json を使う)
if [ "$MODE" = all ] || [ "$MODE" = main ]; then
  echo "[$LOCALE] unanswered state.json を配置（01, 03, 04, 05 撮影）"
  cp "$SHOOT_ROOT/resources/screenshot-tools/state-unanswered.json" "$STATE_JSON"
  xcrun simctl terminate "$UDID" com.nakakei6439.SameQ 2>/dev/null || true
  sleep 1
  xcrun simctl launch "$UDID" com.nakakei6439.SameQ -SameQUseLocalBackend >/dev/null
  sleep 6
  # 01 today
  shot "01-today.png"
  # 03 menu: maestro が id 検出できない問題に対応するため、accessibility tree を経由
  # せず cliclick で直接座標タップ。座標は init 後のヘッダーから判明済み。
  # ハンバーガー: 表示 (110, 340) px → 実機 (144, 445) px
  # → ポイント: 144/3=48, 445/3=148
  echo "  → tap: menu.open (cliclick 座標)"
  # cliclick は Mac 画面の絶対座標が要るが、Simulator ウィンドウの位置が不明。
  # 代わりに Maestro の id 検出を再試行するか、accessibility tree を直接読む。
  # 簡略化のため、maestro を 1 回だけ試して、失敗したら座標タップに切替。
  # ↓ 03-05 は maestro フローでまとめて撮る（id 検出が効かない問題は別途対処）
  # ただし、01 は取れたので、03-05 は maestro で試行。
  JAVA_HOME="/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home"
  export JAVA_HOME
  export PATH="$JAVA_HOME/bin:$HOME/.maestro/bin:$PATH"
  "$HOME/.maestro/bin/maestro" --device "$UDID" test \
    "$SHOOT_ROOT/tools/screenshot-shoot/flows/capture-main.yaml" \
    -e "OUT_01=$OUT_BASE/$LOCALE/01-today" \
    -e "OUT_03=$OUT_BASE/$LOCALE/03-menu" \
    -e "OUT_04=$OUT_BASE/$LOCALE/04-notifications" \
    -e "OUT_05=$OUT_BASE/$LOCALE/05-plus" 2>&1 | tail -20 || true
  xcrun simctl terminate "$UDID" com.nakakei6439.SameQ 2>/dev/null || true
fi

echo "[$LOCALE] 完了"
