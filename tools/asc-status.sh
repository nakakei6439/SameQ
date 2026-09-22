#!/bin/bash
# tools/asc-status.sh
#
# App Store Connect の審査ステータスを毎日チェックする読み取り専用スクリプト。
# GET リクエストのみを発行する。書き込み系リクエスト（PATCH/POST/DELETE）は一切行わない。
#
# 使い方:
#   ./tools/asc-status.sh          人間向けの要約を出力し、前回との差分があれば macOS 通知する
#   ./tools/asc-status.sh --json   正規化した JSON のみを標準出力に出す（自動化向け）
#
# 環境変数（すべて既定値あり。秘密情報ではない）:
#   ASC_KEY_PATH   秘密鍵 .p8 のパス（既定: ~/.appstoreconnect/private_keys/AuthKey_BR882VJ4P8.p8）
#   ASC_KEY_ID     鍵の Key ID（既定: BR882VJ4P8）
#   ASC_ISSUER_ID  Issuer ID（既定: 4a7eba90-53ca-4945-ae45-78facdf6f085）
#   ASC_APP_ID     対象アプリの App ID（既定: 6805425491 = SameQ）
#   ASC_STATE_FILE 前回状態の保存先（既定: <リポジトリ>/.tmp/asc-status-last.json）
#
# 状態は .tmp/asc-status-last.json に保存され、次回実行時との差分検出に使われる。
# .tmp/ は .gitignore 済みなのでリポジトリには含まれない。
# 状態ファイルが壊れている場合は上書きせず、エラーを出して終了コード非0で終わる。
#
# 依存: bash, openssl, python3（標準ライブラリのみ。pyjwt/cryptography は不要）。
# このスクリプトが発行する HTTP メソッドは urllib.request の既定である GET のみ。
#   書き込み系の curl オプションは意図的に一切使用していない。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_BR882VJ4P8.p8}"
ASC_KEY_ID="${ASC_KEY_ID:-BR882VJ4P8}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-4a7eba90-53ca-4945-ae45-78facdf6f085}"
ASC_APP_ID="${ASC_APP_ID:-6805425491}"
ASC_STATE_FILE="${ASC_STATE_FILE:-$REPO_ROOT/.tmp/asc-status-last.json}"

if [ ! -f "$ASC_KEY_PATH" ]; then
  echo "エラー: 秘密鍵が見つかりません: $ASC_KEY_PATH" >&2
  exit 1
fi

mkdir -p "$(dirname "$ASC_STATE_FILE")"

ASC_KEY_PATH="$ASC_KEY_PATH" \
ASC_KEY_ID="$ASC_KEY_ID" \
ASC_ISSUER_ID="$ASC_ISSUER_ID" \
ASC_APP_ID="$ASC_APP_ID" \
ASC_STATE_FILE="$ASC_STATE_FILE" \
python3 - "$@" <<'PYEOF'
import base64
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.request
import urllib.error
from datetime import datetime, timezone, timedelta

# ---- 設定（環境変数から。秘密鍵の「中身」は一切ログに出さない） ----
KEY_PATH = os.environ["ASC_KEY_PATH"]
KID = os.environ["ASC_KEY_ID"]
ISS = os.environ["ASC_ISSUER_ID"]
APP_ID = os.environ["ASC_APP_ID"]
STATE_FILE = os.environ["ASC_STATE_FILE"]

API_BASE = "https://api.appstoreconnect.apple.com/v1"

JSON_ONLY = "--json" in sys.argv[1:]


# ---- 前回状態の読み込み（ネットワークアクセスより先に行い、壊れていれば早期に失敗する） ----
# 「ファイルが存在しない（初回実行）」と「ファイルが存在するが壊れている」を区別する。
# 壊れている場合は絶対に上書きしない（前回の正常な基準値を失わないため）。
state_file_exists = os.path.exists(STATE_FILE)
prev = None
if state_file_exists:
    try:
        with open(STATE_FILE, "r", encoding="utf-8") as f:
            prev = json.load(f)
        if not isinstance(prev, dict):
            raise ValueError("トップレベルがオブジェクトではありません")
    except (json.JSONDecodeError, OSError, UnicodeDecodeError, ValueError) as e:
        sys.stderr.write(f"エラー: 状態ファイルの読み込みに失敗しました: {STATE_FILE}\n")
        sys.stderr.write(f"  詳細: {type(e).__name__}: {e}\n")
        sys.stderr.write(
            "  ファイルが壊れているため、安全のため上書きせずに終了します。"
            "内容を確認するか、意図的にリセットする場合は手動で削除してから再実行してください。\n"
        )
        sys.exit(1)


# ---- ES256 JWT を openssl + 標準ライブラリだけで組み立てる ----
def b64u(b: bytes) -> bytes:
    return base64.urlsafe_b64encode(b).rstrip(b"=")


def der_sig_to_raw(der: bytes) -> bytes:
    # DER SEQUENCE { INTEGER r, INTEGER s } -> raw 64 バイト (r||s, それぞれ32バイト)
    assert der[0] == 0x30
    i = 2
    if der[1] & 0x80:
        i = 2 + (der[1] & 0x7F)
    out = []
    for _ in range(2):
        assert der[i] == 0x02
        ln = der[i + 1]
        v = der[i + 2 : i + 2 + ln]
        i += 2 + ln
        v = v.lstrip(b"\x00").rjust(32, b"\x00")
        out.append(v)
    return out[0] + out[1]


def make_jwt() -> str:
    header = {"alg": "ES256", "kid": KID, "typ": "JWT"}
    now = int(time.time())
    payload = {"iss": ISS, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}
    h = b64u(json.dumps(header, separators=(",", ":")).encode())
    p = b64u(json.dumps(payload, separators=(",", ":")).encode())
    msg = h + b"." + p
    try:
        der = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", KEY_PATH],
            input=msg,
            capture_output=True,
            check=True,
        ).stdout
    except subprocess.CalledProcessError:
        # stderr に鍵の中身が出ることは無いが念のため要点のみ表示
        sys.stderr.write("エラー: JWT 署名に失敗しました（openssl の終了コード異常）\n")
        sys.exit(1)
    sig = b64u(der_sig_to_raw(der))
    return (msg + b"." + sig).decode()


TOKEN = make_jwt()


# ---- HTTP GET 専用クライアント ----
def api_get(path_with_query: str):
    url = API_BASE + path_with_query
    req = urllib.request.Request(url, method="GET")
    req.add_header("Authorization", f"Bearer {TOKEN}")
    req.add_header("Accept", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = resp.read()
            status = resp.status
    except urllib.error.HTTPError as e:
        body = e.read()
        status = e.code
    except urllib.error.URLError as e:
        sys.stderr.write(f"エラー: {url} への接続に失敗しました（ネットワーク不通の可能性）: {e.reason}\n")
        sys.exit(1)
    except OSError as e:
        sys.stderr.write(f"エラー: {url} への接続中に予期しないエラーが発生しました: {e}\n")
        sys.exit(1)

    try:
        data = json.loads(body) if body else {}
    except json.JSONDecodeError:
        sys.stderr.write(f"エラー: {url} のレスポンスが JSON として解析できません（HTTP {status}）\n")
        sys.exit(1)

    if status != 200 or "errors" in data:
        sys.stderr.write(f"エラー: {url} が失敗しました（HTTP {status}）\n")
        sys.stderr.write(json.dumps(data.get("errors", data), ensure_ascii=False, indent=2) + "\n")
        sys.exit(1)
    return data


def qenc(s: str) -> str:
    return s.replace("[", "%5B").replace("]", "%5D")


# ---- 1. reviewSubmissions: 最新1件 ----
rs_path = f"/reviewSubmissions?{qenc('filter[app]')}={APP_ID}&limit=20"
rs_data = api_get(rs_path)
submissions = rs_data.get("data", [])
if not submissions:
    sys.stderr.write("エラー: reviewSubmissions が0件でした\n")
    sys.exit(1)

def submitted_date_key(item):
    d = item.get("attributes", {}).get("submittedDate")
    return d or ""

latest_submission = sorted(submissions, key=submitted_date_key, reverse=True)[0]
sub_id = latest_submission["id"]
sub_attrs = latest_submission.get("attributes", {})
sub_state = sub_attrs.get("state")
sub_submitted_date = sub_attrs.get("submittedDate")

days_since_submission = None
if sub_submitted_date:
    try:
        dt = datetime.fromisoformat(sub_submitted_date.replace("Z", "+00:00"))
        days_since_submission = (datetime.now(timezone.utc) - dt).days
    except ValueError:
        pass

# ---- 2. そのサブミッションの items ----
items_data = api_get(f"/reviewSubmissions/{sub_id}/items")
items = items_data.get("data", [])
item_states = [it.get("attributes", {}).get("state") for it in items]

# ---- 3. appStoreVersions ----
# 注意: このエンドポイントは sort パラメータを受け付けない（400 PARAMETER_ERROR.ILLEGAL）。
# そのため API が返す順序に依存せず、versionString を数値タプルとして解釈して
# 自前で「最新版」を判定する。
versions_path = (
    f"/apps/{APP_ID}/appStoreVersions?limit=5&"
    f"{qenc('fields[appStoreVersions]')}=versionString,appStoreState,appVersionState"
)
versions_data = api_get(versions_path)
versions = versions_data.get("data", [])
version_summaries = [
    {
        "id": v["id"],
        "versionString": v.get("attributes", {}).get("versionString"),
        "appStoreState": v.get("attributes", {}).get("appStoreState"),
        "appVersionState": v.get("attributes", {}).get("appVersionState"),
    }
    for v in versions
]


def version_sort_key(v):
    vs = v.get("versionString") or ""
    parts = []
    for p in vs.split("."):
        try:
            parts.append(int(p))
        except ValueError:
            parts.append(0)
    return tuple(parts)


# ---- 4. 「最新」と判定したバージョンの build ----
build_summary = None
latest_version_string = None
if version_summaries:
    latest_version = max(version_summaries, key=version_sort_key)
    latest_version_id = latest_version["id"]
    latest_version_string = latest_version["versionString"]
    build_path = (
        f"/appStoreVersions/{latest_version_id}/build?"
        f"{qenc('fields[builds]')}=version,processingState,expired,expirationDate"
    )
    build_data = api_get(build_path)
    build = build_data.get("data")
    if build:
        battrs = build.get("attributes", {})
        build_summary = {
            "forVersion": latest_version_string,
            "version": battrs.get("version"),
            "processingState": battrs.get("processingState"),
            "expired": battrs.get("expired"),
            "expirationDate": battrs.get("expirationDate"),
        }

# ---- 5. subscriptionGroups + subscriptions ----
sub_groups_path = f"/apps/{APP_ID}/subscriptionGroups?limit=10&include=subscriptions"
sub_groups_data = api_get(sub_groups_path)
included = sub_groups_data.get("included", [])
subscriptions_summary = []
for inc in included:
    if inc.get("type") == "subscriptions":
        attrs = inc.get("attributes", {})
        subscriptions_summary.append(
            {
                "name": attrs.get("name"),
                "productId": attrs.get("productId"),
                "state": attrs.get("state"),
            }
        )

# ---- 正規化 JSON の組み立て ----
now_utc = datetime.now(timezone.utc)
result = {
    "checkedAt": now_utc.isoformat(),
    "appId": APP_ID,
    "reviewSubmission": {
        "id": sub_id,
        "state": sub_state,
        "submittedDate": sub_submitted_date,
        "daysSinceSubmission": days_since_submission,
        "items": {
            "count": len(item_states),
            "states": item_states,
        },
    },
    "appStoreVersions": version_summaries,
    "latestVersionBuild": build_summary,
    "subscriptions": subscriptions_summary,
}


# ---- 前回状態との比較 ----
# 比較は「意味のあるフィールドだけ」を対象にした構造化ビューで行う。
# - checkedAt / daysSinceSubmission のような、日をまたぐだけで必ず変わる値は対象から除外する
#   （これらを含めると毎日「変化あり」と誤検知して通知がオオカミ少年になる）。
# - リスト項目は versionString / productId をキーにして人間可読な行に展開する
#   （JSON の生文字列化は AppleScript 通知に渡すと引用符の扱いで壊れるため使わない）。
# - キーの区切りは "::" を使う（"." だと versionString "1.0.3" 自体に "." が
#   含まれてしまい、キーの構造を正しく分解できなくなるため）。
SEP = "::"

LABELS = {
    f"reviewSubmission{SEP}state": "審査サブミッション",
    f"reviewSubmission{SEP}id": "審査サブミッションID",
    f"reviewSubmission{SEP}submittedDate": "審査提出日時",
    f"reviewSubmission{SEP}items{SEP}count": "審査アイテム件数",
    f"reviewSubmission{SEP}items{SEP}states": "審査アイテムstate一覧",
    f"latestVersionBuild{SEP}forVersion": "最新ビルドの対象バージョン",
    f"latestVersionBuild{SEP}version": "最新ビルド番号",
    f"latestVersionBuild{SEP}processingState": "最新ビルドのprocessingState",
    f"latestVersionBuild{SEP}expired": "最新ビルドのexpired",
    f"latestVersionBuild{SEP}expirationDate": "最新ビルドの有効期限",
    "latestVersionBuild": "最新ビルド情報",
}


def label_for(key: str) -> str:
    if key in LABELS:
        return LABELS[key]
    parts = key.split(SEP)
    if len(parts) == 3 and parts[0] == "appStoreVersions":
        return f"バージョン{parts[1]}の{parts[2]}"
    if len(parts) == 3 and parts[0] == "subscriptions":
        return f"サブスク{parts[1]}の{parts[2]}"
    return key


def comparable_view(d: dict) -> dict:
    view = {}
    rs = d.get("reviewSubmission") or {}
    view[f"reviewSubmission{SEP}state"] = rs.get("state")
    view[f"reviewSubmission{SEP}id"] = rs.get("id")
    view[f"reviewSubmission{SEP}submittedDate"] = rs.get("submittedDate")
    items_ = rs.get("items") or {}
    view[f"reviewSubmission{SEP}items{SEP}count"] = items_.get("count")
    view[f"reviewSubmission{SEP}items{SEP}states"] = ", ".join(items_.get("states") or [])
    for v in d.get("appStoreVersions") or []:
        ver = v.get("versionString") or "?"
        view[f"appStoreVersions{SEP}{ver}{SEP}appStoreState"] = v.get("appStoreState")
        view[f"appStoreVersions{SEP}{ver}{SEP}appVersionState"] = v.get("appVersionState")
    b = d.get("latestVersionBuild")
    if b:
        view[f"latestVersionBuild{SEP}forVersion"] = b.get("forVersion")
        view[f"latestVersionBuild{SEP}version"] = b.get("version")
        view[f"latestVersionBuild{SEP}processingState"] = b.get("processingState")
        view[f"latestVersionBuild{SEP}expired"] = b.get("expired")
        view[f"latestVersionBuild{SEP}expirationDate"] = b.get("expirationDate")
    else:
        view["latestVersionBuild"] = None
    for s in d.get("subscriptions") or []:
        pid = s.get("productId") or s.get("name") or "?"
        view[f"subscriptions{SEP}{pid}{SEP}state"] = s.get("state")
    return view


changes = []
if prev is not None:
    prev_view = comparable_view(prev)
    new_view = comparable_view(result)
    keys = sorted(set(prev_view) | set(new_view))
    for k in keys:
        old_v = prev_view.get(k, "(なし)")
        new_v = new_view.get(k, "(なし)")
        if old_v != new_v:
            changes.append((k, old_v, new_v))

# ---- 状態保存（アトミック: 同じディレクトリに一時ファイルを書いて os.replace） ----
# 状態ファイルが壊れていた場合はこの行に到達する前に既にエラー終了している。
state_dir = os.path.dirname(os.path.abspath(STATE_FILE)) or "."
fd, tmp_path = tempfile.mkstemp(prefix=".asc-status-", suffix=".tmp", dir=state_dir)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp_path, STATE_FILE)
except Exception:
    if os.path.exists(tmp_path):
        os.remove(tmp_path)
    raise

# ---- macOS 通知（変化があったときだけ）----
# 「osascript が無い環境ではスキップ（エラーにしない）」と
# 「osascript はあるが通知に失敗した（警告を出す）」を区別する。
# 通知本文は argv 経由で AppleScript に渡す（-e の文字列に直接埋め込まない）ため、
# 値に " や \ が含まれていても AppleScript の構文を壊さない。
if prev is not None and changes:
    lines = [f"{label_for(k)}: {ov} -> {nv}" for k, ov, nv in changes[:3]]
    summary = "; ".join(lines)
    if len(summary) > 200:
        summary = summary[:200] + "…"
    title = "SameQ ASC ステータス変化"
    try:
        proc = subprocess.run(
            [
                "osascript",
                "-e", "on run argv",
                "-e", "display notification (item 1 of argv) with title (item 2 of argv)",
                "-e", "end run",
                "--",
                summary,
                title,
            ],
            capture_output=True,
            timeout=10,
            text=True,
        )
        if proc.returncode != 0:
            sys.stderr.write(
                f"警告: macOS 通知の送信に失敗しました（osascript 終了コード {proc.returncode}）\n"
            )
            if proc.stderr:
                sys.stderr.write(f"  {proc.stderr.strip()}\n")
    except FileNotFoundError:
        pass  # osascript が無い環境（macOS 以外等）ではスキップする
    except subprocess.SubprocessError as e:
        sys.stderr.write(f"警告: macOS 通知の送信中にエラーが発生しました: {e}\n")

# ---- 出力 ----
if JSON_ONLY:
    print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    sys.exit(0)

jst_now = datetime.now(timezone.utc).astimezone(timezone(timedelta(hours=9)))
print(f"=== SameQ App Store Connect ステータス ({jst_now.strftime('%Y-%m-%d %H:%M:%S')} JST) ===")
print()
print(f"[審査サブミッション] {sub_id}")
print(f"  state: {sub_state}")
print(f"  submittedDate: {sub_submitted_date}")
if days_since_submission is not None:
    print(f"  経過日数: {days_since_submission} 日")
print(f"  items: {len(item_states)} 件 -> {item_states}")
print()
print("[App Store バージョン]")
for v in version_summaries:
    marker = " (最新と判定)" if v["versionString"] == latest_version_string else ""
    print(
        f"  {v['versionString']}: appStoreState={v['appStoreState']} "
        f"appVersionState={v['appVersionState']}{marker}"
    )
print()
print("[最新バージョンのビルド]")
if build_summary:
    print(f"  対象バージョン: {build_summary['forVersion']}")
    print(
        f"  build {build_summary['version']}: "
        f"processingState={build_summary['processingState']} "
        f"expired={build_summary['expired']} "
        f"expirationDate={build_summary['expirationDate']}"
    )
else:
    print("  (紐づくビルドが見つかりませんでした)")
print()
print("[サブスクリプション]")
for s in subscriptions_summary:
    print(f"  {s['name']} ({s['productId']}): {s['state']}")
print()
if prev is None:
    print("前回の記録が無いため、今回の結果を .tmp/asc-status-last.json に保存しました（差分比較は次回から）。")
elif changes:
    print(f"*** 変化あり（{len(changes)} 件） ***")
    for k, ov, nv in changes:
        print(f"  {label_for(k)}: {ov} -> {nv}")
else:
    print("変化なし")
PYEOF
