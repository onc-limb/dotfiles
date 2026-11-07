#!/usr/bin/env bash
# Claude Code status line script
# Reads JSON from stdin and outputs a 3-line status bar

# ---- jq guard ----
if ! command -v jq &>/dev/null; then
  echo "[statusline] jq not found. Install with: brew install jq" >&2
  echo "model: N/A | context: N/A"
  exit 1
fi

# ---- Read stdin JSON ----
input=$(cat)

# ---- WezTerm のタブバー用に、モデル・コンテキスト・利用制限を書き出す (~/.local/state/agents) ----
printf '%s' "$input" | "$HOME/dotfiles/bin/agent-state" statusline >/dev/null 2>&1

# ---- Extract fields ----
model_name=$(echo "$input" | jq -r '.model.display_name // "Unknown Model"')
transcript_path=$(echo "$input" | jq -r '.transcript_path // ""')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')

# ---- Context window (pre-calculated from JSON) ----
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
remaining_pct=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')
ctx_input=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // empty')
ctx_cache_create=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
ctx_cache_read=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
ctx_output=$(echo "$input" | jq -r '.context_window.current_usage.output_tokens // 0')
ctx_window_size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')

# ---- Rate limits ----
five_pct=$(echo "$input"  | jq -r '.rate_limits.five_hour.used_percentage  // empty')
five_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at       // empty')
week_pct=$(echo "$input"  | jq -r '.rate_limits.seven_day.used_percentage  // empty')
week_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at       // empty')

# ---- Helper: build a progress bar ----
# Usage: make_bar <percentage_float> <width>
make_bar() {
  local pct="$1"
  local width="${2:-10}"
  if [ -z "$pct" ]; then
    printf "N/A"
    return
  fi
  # filled = round(pct / 100 * width)
  local filled=$(echo "$pct $width" | awk '{printf "%d", ($1/100*$2 + 0.5)}')
  local empty=$(( width - filled ))
  local bar="["
  local i
  for (( i=0; i<filled; i++ )); do bar="${bar}█"; done
  for (( i=0; i<empty;  i++ )); do bar="${bar}░"; done
  bar="${bar}]"
  printf "%s" "$bar"
}

# ---- Helper: format reset time ----
fmt_reset() {
  local epoch="$1"
  local fmt="${2:-+%H:%M}"
  [ -z "$epoch" ] && { printf "N/A"; return; }
  # macOS date -r
  date -r "$epoch" "$fmt" 2>/dev/null || printf "N/A"
}

# ---- Helper: format percentage ----
fmt_pct() {
  local pct="$1"
  [ -z "$pct" ] && { printf "N/A%%"; return; }
  printf "%.0f%%" "$pct"
}

# ---- ANSI colors (dimmed-friendly) ----
RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"
C_CYAN="\033[36m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_MAGENTA="\033[35m"
C_BLUE="\033[34m"
C_RED="\033[31m"

# ---- Context color based on usage ----
ctx_color="$C_GREEN"
if [ -n "$used_pct" ]; then
  used_int=$(printf "%.0f" "$used_pct")
  if   [ "$used_int" -ge 85 ]; then ctx_color="$C_RED"
  elif [ "$used_int" -ge 60 ]; then ctx_color="$C_YELLOW"
  fi
fi

# ---- Line 1: Model + Context usage ----
if [ -n "$used_pct" ]; then
  ctx_bar=$(make_bar "$used_pct" 20)
  ctx_label="$(fmt_pct "$used_pct") used"
else
  ctx_bar="[░░░░░░░░░░░░░░░░░░░░]"
  ctx_label="N/A"
fi

printf "${BOLD}${C_CYAN}%s${RESET}  ${BOLD}${ctx_color}ctx${RESET} ${ctx_color}%s${RESET}  ${BOLD}%s${RESET}\n" \
  "$model_name" \
  "$ctx_bar" \
  "$ctx_label"

# ---- Line 2: Quota (5h + 7d) ----
# WezTerm の中ではタブバーに利用制限を出すので、ここでは省く (Orca / Zed などでは従来どおり表示)
if [ -z "${WEZTERM_PANE:-}" ]; then
five_bar="N/A"
five_label="N/A"
five_reset_str="N/A"
week_bar="N/A"
week_label="N/A"
week_reset_str="N/A"

if [ -n "$five_pct" ]; then
  five_bar=$(make_bar "$five_pct" 15)
  five_label=$(fmt_pct "$five_pct")
  five_reset_str=$(fmt_reset "$five_reset")
fi

if [ -n "$week_pct" ]; then
  week_bar=$(make_bar "$week_pct" 15)
  week_label=$(fmt_pct "$week_pct")
  week_reset_str=$(fmt_reset "$week_reset" "+%m/%d %H:%M")
fi

printf "${BOLD}${C_YELLOW}5h${RESET}  ${C_YELLOW}%s${RESET} ${BOLD}%s${RESET} ${DIM}→%s${RESET}   ${BOLD}${C_MAGENTA}7d${RESET}  ${C_MAGENTA}%s${RESET} ${BOLD}%s${RESET} ${DIM}→%s${RESET}\n" \
  "$five_bar" "$five_label" "$five_reset_str" \
  "$week_bar" "$week_label" "$week_reset_str"
fi

# ---- Line 3: Directory (parent/current) + git branch ----
# WezTerm の中ではタブバーの左にディレクトリとブランチを出すので、ここでは省く
[ -n "${WEZTERM_PANE:-}" ] && exit 0
git_branch=""
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  git_branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null \
    || git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
fi

# Show parent/current only (one level up)
if [ -n "$cwd" ]; then
  parent_name=$(basename "$(dirname "$cwd")")
  current_name=$(basename "$cwd")
  if [ "$parent_name" = "/" ] || [ -z "$parent_name" ]; then
    short_path="$current_name"
  else
    short_path="$parent_name/$current_name"
  fi
else
  short_path="?"
fi

if [ -n "$git_branch" ]; then
  printf "${C_BLUE}%s${RESET}  ${C_GREEN} %s${RESET}\n" "$short_path" "$git_branch"
else
  printf "${C_BLUE}%s${RESET}\n" "$short_path"
fi
