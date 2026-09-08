#!/bin/sh
# Claude Code の PostToolUse (Bash) フック。
# codex プラグイン (codex-companion.mjs) が Codex をバックグラウンドで起動したのを検知し、
# その Codex ジョブが終わるまで Herdr のサイドバーでこのペインを「作業中」に見せる。
#
# 背景: Herdr は Claude Code の状態を画面から判定し、最優先はターミナルタイトルの先頭の
# スピナー (◐ … = working / ✳ … = idle)。Claude 用ペインでは socket API の report-agent は
# 無視される (画面判定が唯一の権威)。Codex をバックグラウンド起動すると Claude のターンは
# 即終了して idle 表示になるため、Codex ジョブの完了を別プロセスで待ちながら、ペインの tty に
# OSC 0 で「◐ Codex: …」のタイトルを書き続ける。終わったら Claude 側のタイトルを ✳ で戻す
# (working → idle の変化で Herdr の完了通知も鳴る)。
#
# 注意: タイトルの優先度が最も高いため、待っている間に Claude へ別の指示を出して
# 許可待ち (blocked) になってもサイドバーは working のまま。
#
# 使い方: settings.json の hooks.PostToolUse (matcher: Bash) から `bash <this> ` で呼ぶ。
#         内部で `<this> watch ...` として自身を監視プロセスとして再起動する。

set -u

# ---------- 監視プロセス ----------
if [ "${1:-}" = "watch" ]; then
	tty_dev="$2"; script="$3"; cwd="$4"; job_id="$5"; title="$6"; marker="$7"; pane="$8"
	state_dir="$(dirname "$marker")"
	our_title="◐ Codex: ${title:-task} ($job_id)"

	current_title() {
		herdr agent get "$pane" 2>/dev/null | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin)["result"]["agent"]["terminal_title"])
except Exception:
    pass'
	}
	set_title() {
		printf '\033]0;%s\007' "$1" >"$tty_dev" 2>/dev/null
	}
	job_status() {
		(cd "$cwd" && node "$script" status "$job_id" --json 2>/dev/null) | python3 -c '
import json, sys
try:
    print(((json.load(sys.stdin) or {}).get("job") or {}).get("status") or "")
except Exception:
    print("")'
	}

	# Claude 自身が最後に付けたタイトル (復元用)。フック実行時点は Claude のターン中なので ◐ 付き
	last_claude_title="$(current_title)"
	tick=0
	deadline=$(( $(date +%s) + 6 * 3600 ))
	while [ "$(date +%s)" -lt "$deadline" ]; do
		if [ $(( tick % 3 )) -eq 0 ]; then
			case "$(job_status)" in
			queued | running) ;;
			*) break ;;
			esac
		fi
		# Claude が自分でタイトルを更新していたら覚えておく (復元時に使う)
		now="$(current_title)"
		if [ -n "$now" ] && [ "$now" != "$our_title" ]; then
			last_claude_title="$now"
		fi
		set_title "$our_title" || break
		tick=$(( tick + 1 ))
		sleep 3
	done

	rm -f "$marker"
	# 同じペインで他の Codex ジョブがまだ走っていればタイトルはそちらに任せる
	if [ -z "$(ls -A "$state_dir" 2>/dev/null)" ]; then
		# 先頭のスピナー / 状態グリフを外して idle (✳) として戻す。Claude がターン中なら
		# スピナーのアニメーションですぐ上書きされるので問題ない
		stripped="$(printf '%s' "$last_claude_title" | python3 -c '
import re, sys
t = sys.stdin.read()
print(re.sub(r"^[⠀-⣿◐-◓✳✶✻✽·•*]\s*", "", t))')"
		set_title "✳ ${stripped:-Codex done}"
	fi
	exit 0
fi

# ---------- フック本体 ----------
[ "${HERDR_ENV:-}" = "1" ] || exit 0
[ -n "${HERDR_PANE_ID:-}" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0
command -v herdr >/dev/null 2>&1 || PATH="$HOME/.local/bin:$PATH"
command -v herdr >/dev/null 2>&1 || exit 0

# フック入力 (JSON) から companion のパス / cwd / ジョブ ID / タイトルを取り出す。
# 対象は Bash ツールで codex-companion.mjs を呼び、出力に
# "<title> started in the background as <jobId>." を含むものだけ。
# このフックは全ての Bash 呼び出しで動くので、python3 を起動する前に文字列で足切りする
input="$(cat)"
case "$input" in
*codex-companion.mjs*"started in the background as"*) ;;
*) exit 0 ;;
esac
parsed="$(printf '%s' "$input" | python3 -c '
import json, re, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if data.get("tool_name") != "Bash":
    sys.exit(0)
command = str((data.get("tool_input") or {}).get("command") or "")
m = re.search(r"\"?(\S*?codex-companion\.mjs)\"?", command)
if not m:
    sys.exit(0)
script = m.group(1)
response = data.get("tool_response")
text = response if isinstance(response, str) else json.dumps(response, ensure_ascii=False)
m = re.search(r"(?P<title>[^\n\"]*?) started in the background as (?P<job>[A-Za-z0-9_.:-]+?)\.?(?:\s|\\n|\"|$)", text)
if not m:
    sys.exit(0)
print(script)
print(data.get("cwd") or "")
print(m.group("job"))
print(m.group("title").strip())
')"
[ -n "$parsed" ] || exit 0

script="$(printf '%s\n' "$parsed" | sed -n 1p)"
cwd="$(printf '%s\n' "$parsed" | sed -n 2p)"
job_id="$(printf '%s\n' "$parsed" | sed -n 3p)"
title="$(printf '%s\n' "$parsed" | sed -n 4p)"
[ -n "$job_id" ] || exit 0
[ -f "$script" ] || exit 0
[ -d "$cwd" ] || cwd="$PWD"

# ペインの tty。フックの親プロセスが claude 本体なのでその tty を使う。
# 取れなければ Herdr にペインのシェル PID を聞いてそちらの tty を使う
tty_name="$(ps -o tty= -p "$PPID" 2>/dev/null | tr -d ' ')"
if [ -z "$tty_name" ] || [ "$tty_name" = "??" ]; then
	shell_pid="$(herdr pane process-info --pane "$HERDR_PANE_ID" 2>/dev/null | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin)["result"]["process_info"]["shell_pid"])
except Exception:
    pass')"
	[ -n "$shell_pid" ] && tty_name="$(ps -o tty= -p "$shell_pid" 2>/dev/null | tr -d ' ')"
fi
[ -n "$tty_name" ] && [ "$tty_name" != "??" ] || exit 0
tty_dev="/dev/$tty_name"
[ -w "$tty_dev" ] || exit 0

# 同じペインで複数ジョブが走っても、最後の 1 つが終わるまでタイトルを戻さないよう
# ジョブごとのマーカーファイルで数える
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/herdr-codex-watch/$(printf '%s' "$HERDR_PANE_ID" | tr -c 'A-Za-z0-9' '_')"
mkdir -p "$state_dir"
marker="$state_dir/$job_id"
: >"$marker"

# フックは即終了させたいので監視プロセスは切り離す
nohup sh "$0" watch "$tty_dev" "$script" "$cwd" "$job_id" "$title" "$marker" "$HERDR_PANE_ID" >/dev/null 2>&1 &
exit 0
