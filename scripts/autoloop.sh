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
#   - blocked（3-strike）は最終スプリントでない限り停止せず次のスプリントへ自動スキップする
#     （2026-08-28 ユーザー方針: 人間判断待ちで完全停止するより進められる分を進める）
#   - 利用上限・レート制限などの一時的なエラーは、最大 MAX_TRANSIENT_RETRIES 回まで
#     TRANSIENT_RETRY_WAIT 秒ずつ待って自動リトライする（2026-08-27 深夜、利用上限で
#     停止したまま誰にも気づかれず約10時間放置された事故の再発防止）

set -uo pipefail

REPO_DIR="/Users/nakagawakeita/Products/iOSApp/SameQ"
STATE_FILE="$REPO_DIR/.product/state.json"
LOGDIR="$REPO_DIR/.product/autoloop-logs"
LOCK_FILE="$REPO_DIR/.product/autoloop.lock"
MAX_ITERATIONS="${MAX_ITERATIONS:-60}"
LAST_SPRINT="17"
TIMEOUT_SECONDS=14400
TIMEOUT_SENTINEL="$LOGDIR/.timeout_fired"
MAX_TRANSIENT_RETRIES=6
TRANSIENT_RETRY_WAIT=1200

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
    log "既に autoloop.sh が実行中です（PID ${existing_pid}）。多重起動を防ぐため終了します。"
    exit 9
  fi
  log "古いロックファイル（PID ${existing_pid}、既に終了済み）を上書きします。"
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

is_transient_limit_error() {
  # 利用上限・レート制限など、時間が経てば自然に解消する可能性が高いエラーかを判定する。
  # 該当すれば true を返し、呼び出し側で待機・自動リトライの対象にする。
  local logfile="$1"
  grep -qiE "spend limit|usage limit|rate limit|Request rejected \(429\)" "$logfile" 2>/dev/null
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

skip_blocked_sprint() {
  # blocked（3-strike）になったスプリントを history に記録した上で次のスプリントへ進める。
  # ユーザー方針（2026-08-28）: 人間の判断待ちで完全に止まるより、進められる分は進める。
  local current="$1" attempt_num="$2"
  python3 -c "
import json
with open('$STATE_FILE') as f:
    d = json.load(f)
current = int(d['currentSprint'])
next_sprint = f'{current + 1:02d}'
d['history'].append({
    'sprint': d['currentSprint'],
    'attempt': int(d['attempt']),
    'result': 'skipped_blocked',
    'note': 'autoloop: blocked（3-strike）のため自動スキップ。ユーザー方針により人間判断待ちで止めず次のスプリントへ進めた。このスプリントは後で人間が個別に再開する必要がある。詳細は .product/sprints/ 配下の self-review.md を参照。'
})
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
      if [ "$current_sprint" = "$LAST_SPRINT" ]; then
        log "generator が blocked 状態です（同じ指摘で複数回失敗）。スプリント $LAST_SPRINT は最終スプリントのため、これ以上進められません。人間の判断が必要なため停止します。"
        commit_if_changed "autoloop: SAFETY-NET commit before exit 2 (blocked, sprint=${current_sprint}, attempt=${attempt})"
        exit 2
      fi
      log "generator が blocked 状態です（同じ指摘で複数回失敗、人間の判断が必要）。ユーザー方針により停止せず、次のスプリントへ自動スキップします。"
      next=$(skip_blocked_sprint "$current_sprint" "$attempt")
      log "スプリント $current_sprint は blocked のままスキップ。次のスプリント $next へ進みます。"
      commit_if_changed "autoloop: skip blocked sprint $current_sprint, advance to $next"
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
      gen_retry=0
      while :; do
        gen_log="$LOGDIR/generator_$(date +%Y%m%d_%H%M%S).log"
        log "generator を起動します（sprint=${current_sprint}）..."
        with_timeout "$TIMEOUT_SECONDS" stdbuf -oL -eL env -u ANTHROPIC_API_KEY -u CLAUDE_CODE_AUTH_TOKEN \
          ANTHROPIC_BASE_URL='https://api.minimax.io/anthropic' \
          ANTHROPIC_AUTH_TOKEN="$MINIMAX_API_KEY" \
          ANTHROPIC_MODEL="MiniMax-M3 [im]" \
          claude --agent generator -p \
            "PROGRESS.md と .product/state.json を読んで、現在のスプリントの実装または修正を行い、self-review.md を書いてください。" \
          --permission-mode bypassPermissions \
          --output-format text >> "$gen_log" 2>&1
        gen_exit=$?

        if [ "$gen_exit" -ne 0 ] && [ ! -f "$TIMEOUT_SENTINEL" ] && is_transient_limit_error "$gen_log" && [ "$gen_retry" -lt "$MAX_TRANSIENT_RETRIES" ]; then
          gen_retry=$((gen_retry + 1))
          log "generator が利用上限系のエラーで失敗しました（exit=${gen_exit}）。一時的な制限とみなし、${TRANSIENT_RETRY_WAIT}秒待って自動リトライします（${gen_retry}/${MAX_TRANSIENT_RETRIES}回目）。"
          sleep "$TRANSIENT_RETRY_WAIT"
          continue
        fi
        break
      done

      new_status=$(read_state status)
      if [ "$gen_exit" -ne 0 ]; then
        if [ -f "$TIMEOUT_SENTINEL" ]; then
          log "generator の実行がタイムアウト（${TIMEOUT_SECONDS}秒）でSIGTERMされました（exit=${gen_exit}）。クラッシュではなくタイムアウトです。停止します。"
        elif [ "$gen_retry" -ge "$MAX_TRANSIENT_RETRIES" ]; then
          log "generator が利用上限系のエラーで ${MAX_TRANSIENT_RETRIES} 回自動リトライ（計 $((MAX_TRANSIENT_RETRIES * TRANSIENT_RETRY_WAIT / 60))分待機）しましたが解消しませんでした（exit=${gen_exit}）。停止します。ログを確認してください。"
        else
          log "generator の実行がエラー終了しました（exit=${gen_exit}）。停止します。ログを確認してください。"
        fi
        commit_if_changed "autoloop: SAFETY-NET commit before exit 3 (gen_exit=${gen_exit}, sprint=${current_sprint}, attempt=${attempt})"
        exit 3
      fi
      if [ "$new_status" = "blocked" ]; then
        log "generator が blocked に遷移しました（3-strike等）。次のiterationでblocked分岐（自動スキップ/停止判定）に委ねます。"
        commit_if_changed "autoloop: generator sprint=$current_sprint attempt=$attempt (blocked)"
        continue
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
      eval_retry=0
      while :; do
        eval_log="$LOGDIR/evaluator_$(date +%Y%m%d_%H%M%S).log"
        log "evaluator を起動します（sprint=${current_sprint}）..."
        with_timeout "$TIMEOUT_SECONDS" stdbuf -oL -eL claude --agent evaluator -p \
          "PROGRESS.md と .product/state.json を読んで、現在のスプリントを実際に動かして評価してください。重要: これは非対話・一回きりの実行です。バックグラウンドでテストを実行して「後で報告します」という形で終わらせることはできません（このプロセスはこのターンが終われば消え、フォローアップは一切発生しません）。フルテストスイートやビルドがどれだけ時間がかかっても、必ず全て完了させてから、このターン内で合否判定・eval-N.mdの作成・state.jsonのstatus更新まで完結させてください。" \
          --permission-mode bypassPermissions \
          --output-format text >> "$eval_log" 2>&1
        eval_exit=$?

        if [ "$eval_exit" -ne 0 ] && [ ! -f "$TIMEOUT_SENTINEL" ] && is_transient_limit_error "$eval_log" && [ "$eval_retry" -lt "$MAX_TRANSIENT_RETRIES" ]; then
          eval_retry=$((eval_retry + 1))
          log "evaluator が利用上限系のエラーで失敗しました（exit=${eval_exit}）。一時的な制限とみなし、${TRANSIENT_RETRY_WAIT}秒待って自動リトライします（${eval_retry}/${MAX_TRANSIENT_RETRIES}回目）。"
          sleep "$TRANSIENT_RETRY_WAIT"
          continue
        fi
        break
      done

      new_status=$(read_state status)
      if [ "$eval_exit" -ne 0 ]; then
        if [ -f "$TIMEOUT_SENTINEL" ]; then
          log "evaluator の実行がタイムアウト（${TIMEOUT_SECONDS}秒）でSIGTERMされました（exit=${eval_exit}）。クラッシュではなくタイムアウトです。停止します。"
        elif [ "$eval_retry" -ge "$MAX_TRANSIENT_RETRIES" ]; then
          log "evaluator が利用上限系のエラーで ${MAX_TRANSIENT_RETRIES} 回自動リトライ（計 $((MAX_TRANSIENT_RETRIES * TRANSIENT_RETRY_WAIT / 60))分待機）しましたが解消しませんでした（exit=${eval_exit}）。停止します。ログを確認してください。"
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
