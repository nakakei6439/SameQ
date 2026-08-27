#!/bin/bash
# SameQ 夜間無人実行ループ
#
# generator（MiniMax-M3）と evaluator（Sonnet）を .product/state.json の status に応じて
# 交互に非対話（-p）で起動し、スプリント 01〜11 がすべて passed になるまで繰り返す。
#
# 起動: nohup caffeinate -i ./scripts/autoloop.sh > .product/autoloop-logs/main.log 2>&1 &
# 停止: pkill -f autoloop.sh
#
# 安全装置:
#   - 各 claude 呼び出しに timeout 14400s（4時間）。タイムアウトによるkillと
#     本物のクラッシュは sentinel ファイル（.timeout_fired）で区別してログに記録する。
#   - 反復回数の上限 MAX_ITERATIONS
#   - status が期待通り遷移しなかったら異常終了
#   - blocked / 全スプリント完了で正常終了
#   - どの異常終了パスでも、抜ける前に必ず commit_if_changed を呼び、未コミットの
#     作業がluckに依存して残る状態を作らない（2026-08-27 sprint12 タイムアウト事故の教訓）

set -uo pipefail

REPO_DIR="/Users/nakagawakeita/Products/iOSApp/SameQ"
STATE_FILE="$REPO_DIR/.product/state.json"
LOGDIR="$REPO_DIR/.product/autoloop-logs"
LOCK_FILE="$REPO_DIR/.product/autoloop.lock"
MAX_ITERATIONS="${MAX_ITERATIONS:-60}"
LAST_SPRINT="17"
TIMEOUT_SECONDS=14400
TIMEOUT_SENTINEL="$LOGDIR/.timeout_fired"

mkdir -p "$LOGDIR"
cd "$REPO_DIR" || { echo "リポジトリに移動できません: $REPO_DIR"; exit 1; }

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGDIR/main.log"
}

# 多重起動防止: 生きている別プロセスのロックがあれば即座に終了する。
# ロックファイルにPIDを記録し、そのPIDが実在しなければ古いロックとみなして上書きする。
if [ -f "$LOCK_FILE" ]; then
  existing_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
  if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
    log "既に autoloop.sh が実行中です（PID $existing_pid）。多重起動を防ぐため終了します。"
    exit 9
  fi
  log "古いロックファイル（PID $existing_pid、既に終了済み）を上書きします。"
fi
echo "$$" > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

read_state() {
  # $1: JSONキー (currentSprint / attempt / status)
  python3 -c "
import json, sys
with open('$STATE_FILE') as f:
    d = json.load(f)
print(d.get('$1', ''))
"
}

with_timeout() {
  # macOS 標準には GNU の timeout コマンドが無いため、bash だけで実装する。
  # $1: タイムアウト秒数。残りの引数がコマンド。
  # タイムアウトで実際にkillした場合は $TIMEOUT_SENTINEL を作成し、
  # 呼び出し側が「クラッシュ」ではなく「タイムアウト」だと判別できるようにする。
  local secs="$1"; shift
  rm -f "$TIMEOUT_SENTINEL"
  "$@" &
  local pid=$!
  (
    sleep "$secs"
    if kill -0 "$pid" 2>/dev/null; then
      touch "$TIMEOUT_SENTINEL"
      kill -TERM "$pid" 2>/dev/null
      sleep 5
      kill -KILL "$pid" 2>/dev/null
    fi
  ) &
  local watchdog=$!
  wait "$pid" 2>/dev/null
  local status=$?
  kill "$watchdog" 2>/dev/null
  wait "$watchdog" 2>/dev/null
  return "$status"
}

commit_if_changed() {
  local msg="$1"
  if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git status --porcelain)" ]; then
    git add -A
    git commit -m "$msg" >> "$LOGDIR/git.log" 2>&1
    log "git commit: $msg"
  fi
}

advance_to_next_sprint() {
  python3 -c "
import json
with open('$STATE_FILE') as f:
    d = json.load(f)
current = int(d['currentSprint'])
next_sprint = f'{current + 1:02d}'
d['currentSprint'] = next_sprint
d['attempt'] = 1
d['status'] = 'in_progress'
with open('$STATE_FILE', 'w') as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
print(next_sprint)
"
}

if [ ! -f "$STATE_FILE" ]; then
  log "エラー: $STATE_FILE が見つかりません。停止します。"
  exit 1
fi

log "===== autoloop 開始 ====="

iteration=0
while [ "$iteration" -lt "$MAX_ITERATIONS" ]; do
  iteration=$((iteration + 1))

  current_sprint=$(read_state currentSprint)
  status=$(read_state status)
  attempt=$(read_state attempt)

  log "--- iteration $iteration: sprint=$current_sprint attempt=$attempt status=$status ---"

  case "$status" in
    blocked)
      log "generator が blocked 状態です（同じ指摘で複数回失敗）。人間の判断が必要なため停止します。"
      commit_if_changed "autoloop: SAFETY-NET commit before exit 2 (blocked, sprint=${current_sprint}, attempt=${attempt})"
      exit 2
      ;;

    passed)
      if [ "$current_sprint" = "$LAST_SPRINT" ]; then
        log "スプリント $LAST_SPRINT が passed。全スプリント完了。正常終了します。"
        exit 0
      fi
      next=$(advance_to_next_sprint)
      log "スプリント $current_sprint が passed。次のスプリント $next へ進みます。"
      commit_if_changed "autoloop: advance to sprint $next"
      ;;

    in_progress | needs_fix)
      log "generator を起動します（sprint=${current_sprint}）..."
      with_timeout "$TIMEOUT_SECONDS" stdbuf -oL -eL env -u ANTHROPIC_API_KEY -u CLAUDE_CODE_AUTH_TOKEN \
        ANTHROPIC_BASE_URL='https://api.minimax.io/anthropic' \
        ANTHROPIC_AUTH_TOKEN="$MINIMAX_API_KEY" \
        ANTHROPIC_MODEL="MiniMax-M3 [im]" \
        claude --agent generator -p \
          "PROGRESS.md と .product/state.json を読んで、現在のスプリントの実装または修正を行い、self-review.md を書いてください。" \
        --permission-mode bypassPermissions \
        --output-format text >> "$LOGDIR/generator_$(date +%Y%m%d_%H%M%S).log" 2>&1
      gen_exit=$?

      new_status=$(read_state status)
      if [ "$gen_exit" -ne 0 ]; then
        if [ -f "$TIMEOUT_SENTINEL" ]; then
          log "generator の実行がタイムアウト（${TIMEOUT_SECONDS}秒）でSIGTERMされました（exit=${gen_exit}）。クラッシュではなくタイムアウトです。停止します。"
        else
          log "generator の実行がエラー終了しました（exit=${gen_exit}）。停止します。ログを確認してください。"
        fi
        commit_if_changed "autoloop: SAFETY-NET commit before exit 3 (gen_exit=${gen_exit}, sprint=${current_sprint}, attempt=${attempt})"
        exit 3
      fi
      if [ "$new_status" != "awaiting_eval" ]; then
        log "generator 実行後も status が awaiting_eval になりませんでした（現在: ${new_status}）。想定外のため停止します。"
        commit_if_changed "autoloop: SAFETY-NET commit before exit 4 (sprint=${current_sprint}, attempt=${attempt})"
        exit 4
      fi
      log "generator 完了。status=$new_status"
      commit_if_changed "autoloop: generator sprint=$current_sprint attempt=$attempt"
      ;;

    awaiting_eval)
      log "evaluator を起動します（sprint=${current_sprint}）..."
      with_timeout "$TIMEOUT_SECONDS" stdbuf -oL -eL claude --agent evaluator -p \
        "PROGRESS.md と .product/state.json を読んで、現在のスプリントを実際に動かして評価してください。重要: これは非対話・一回きりの実行です。バックグラウンドでテストを実行して「後で報告します」という形で終わらせることはできません（このプロセスはこのターンが終われば消え、フォローアップは一切発生しません）。フルテストスイートやビルドがどれだけ時間がかかっても、必ず全て完了させてから、このターン内で合否判定・eval-N.mdの作成・state.jsonのstatus更新まで完結させてください。" \
        --permission-mode bypassPermissions \
        --output-format text >> "$LOGDIR/evaluator_$(date +%Y%m%d_%H%M%S).log" 2>&1
      eval_exit=$?

      new_status=$(read_state status)
      if [ "$eval_exit" -ne 0 ]; then
        if [ -f "$TIMEOUT_SENTINEL" ]; then
          log "evaluator の実行がタイムアウト（${TIMEOUT_SECONDS}秒）でSIGTERMされました（exit=${eval_exit}）。クラッシュではなくタイムアウトです。停止します。"
        else
          log "evaluator の実行がエラー終了しました（exit=${eval_exit}）。停止します。ログを確認してください。"
        fi
        commit_if_changed "autoloop: SAFETY-NET commit before exit 5 (eval_exit=${eval_exit}, sprint=${current_sprint}, attempt=${attempt})"
        exit 5
      fi
      if [ "$new_status" != "passed" ] && [ "$new_status" != "needs_fix" ] && [ "$new_status" != "blocked" ]; then
        log "evaluator 実行後も status が passed/needs_fix/blocked になりませんでした（現在: ${new_status}）。想定外のため停止します。"
        commit_if_changed "autoloop: SAFETY-NET commit before exit 6 (sprint=${current_sprint}, attempt=${attempt})"
        exit 6
      fi
      log "evaluator 完了。status=$new_status"
      commit_if_changed "autoloop: evaluator sprint=$current_sprint"
      ;;

    *)
      log "未知の status です: ${status}。想定外のため停止します。"
      exit 7
      ;;
  esac
done

log "反復回数の上限（${MAX_ITERATIONS}）に達しました。安全のため停止します。"
exit 8
