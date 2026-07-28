#!/usr/bin/env bash
# workspace 1 を「Zen: 左 1/3 / WezTerm: 右 2/3」に整える。
#
# AeroSpace には「このアプリの幅を常に 1/3」という宣言的な設定が無いため、
# aerospace CLI (move / resize --window-id) で明示的に組み直す。
# aerospace.toml の on-window-detected と alt-ctrl-1 から呼ばれる。
#
# ASSUMPTION: 「1番 window」= workspace 1 のこと、と解釈している。
set -euo pipefail

WS=1
ZEN_APP_ID='app.zen-browser.zen'
WEZ_APP_ID='com.github.wez.wezterm'
LEFT_DENOM=3 # 左（Zen）の割合 = 1/3

# aerospace.toml の [gaps] と揃えること
GAP_OUTER=5
GAP_INNER=5

windows=$(aerospace list-windows --workspace "$WS" \
  --format '%{window-id} %{app-bundle-id} %{monitor-appkit-nsscreen-screens-id}')

[ -n "$windows" ] || exit 0

zen_id=$(awk -v a="$ZEN_APP_ID" '$2 == a { print $1; exit }' <<<"$windows")
wez_id=$(awk -v a="$WEZ_APP_ID" '$2 == a { print $1; exit }' <<<"$windows")

# 2つが揃っていないときは触らない
[ -n "$zen_id" ] && [ -n "$wez_id" ] || exit 0

# 他のウィンドウが混ざっていると 1/3・2/3 が破綻するのでそのままにする
[ "$(wc -l <<<"$windows")" -eq 2 ] || exit 0

# workspace 1 が乗っているモニターの幅（NSScreen.screens は 1 始まりの index で参照される）
screen_idx=$(awk '{ print $3; exit }' <<<"$windows")
screen_w=$(osascript -l JavaScript \
  -e "ObjC.import('AppKit'); \$.NSScreen.screens.js[$screen_idx - 1].frame.size.width")
screen_w=${screen_w%%.*}

[ -n "$screen_w" ] && [ "$screen_w" -gt 0 ] || exit 1

# 外側の余白と 2 ペイン間の余白を除いた実描画幅を 1/3 で割る
zen_w=$(((screen_w - GAP_OUTER * 2 - GAP_INNER) / LEFT_DENOM))

# AeroSpace は「状態が変わらなかった」コマンドも終了コード 1 を返す
# （例: 既に h_tiles のときの layout、既に左端のときの move）。
# ここでは冪等に流したいので失敗を許容する。
step() {
  aerospace "$@" || true
}

step flatten-workspace-tree --workspace "$WS"
step layout --window-id "$zen_id" h_tiles
step move --window-id "$zen_id" --boundaries workspace --boundaries-action stop left
step resize --window-id "$zen_id" width "$zen_w"
