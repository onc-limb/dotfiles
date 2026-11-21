#!/usr/bin/env bash
# Tests for bin/takt's environment selection (work / private).
#
#   bash takt/tests/test_wrapper.sh            # with the bash running this script
#   TEST_BASH=/bin/bash bash takt/tests/test_wrapper.sh   # with macOS bash 3.2
#
# A fake `takt` behind the wrapper prints the environment and arguments it got.
# HOME is a temporary directory laid out like the real one (~/work,
# ~/Documents/onclimb-industries).
set -euo pipefail

dotfiles="$(cd "$(dirname "$0")/../.." && pwd)"
wrapper="$dotfiles/bin/takt"
test_bash="${TEST_BASH:-$BASH}"

tmp="$(realpath "$(mktemp -d)")"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
mkdir -p "$HOME/work" "$HOME/Documents/onclimb-industries" "$HOME/elsewhere" "$tmp/bin-wrapper" "$tmp/bin-real"
ln -s "$wrapper" "$tmp/bin-wrapper/takt"
cat > "$tmp/bin-real/takt" <<'EOF'
#!/bin/sh
echo "TAKT_CONFIG_DIR=${TAKT_CONFIG_DIR-<unset>}"
echo "ANTHROPIC_PROFILE=${ANTHROPIC_PROFILE-<unset>}"
echo "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY-<unset>}"
echo "ANTHROPIC_CONFIG_DIR=${ANTHROPIC_CONFIG_DIR-<unset>}"
echo "OPENAI_API_KEY=${OPENAI_API_KEY-<unset>}"
echo "TAKT_OPENROUTER_API_KEY=${TAKT_OPENROUTER_API_KEY-<unset>}"
echo "CLAUDE_CODE_USE_BEDROCK=${CLAUDE_CODE_USE_BEDROCK-<unset>}"
echo "TAKT_OPENCODE_PATH=${TAKT_OPENCODE_PATH-<unset>}"
echo "ARGS=$*"
EOF
chmod +x "$tmp/bin-real/takt"
export PATH="$tmp/bin-wrapper:$tmp/bin-real:/usr/bin:/bin"
unset TAKT_CONFIG_DIR TAKT_BILLING ANTHROPIC_PROFILE 2> /dev/null || true

private_root="$HOME/Documents/onclimb-industries"
work_cfg="$HOME/.takt-work"
private_cfg="$HOME/.takt-private"

pass=0
fail=0
ok() { pass=$((pass + 1)); }
ng() { fail=$((fail + 1)); printf 'FAIL: %s\n%s\n' "$1" "$2" >&2; }

mkproj() { # mkproj DIR [MARKER_CONTENT]
  mkdir -p "$1/.takt"
  git -C "$1" init -q
  if [[ $# -ge 2 ]]; then printf '%s\n' "$2" > "$1/.takt/private.conf"; fi
}

# run DIR [ENV=VALUE ...] -- ARGS...  -> sets $out and $code
run() {
  local dir="$1"; shift
  local envs=()
  while [[ $# -gt 0 && "$1" != "--" ]]; do envs+=("$1"); shift; done
  [[ "${1:-}" == "--" ]] && shift
  code=0
  out="$(cd "$dir" && env ${envs[@]+"${envs[@]}"} "$test_bash" "$tmp/bin-wrapper/takt" "$@" 2>&1)" || code=$?
}

expect_line() { # NAME LINE
  if [[ $code -eq 0 ]] && grep -qxF -- "$2" <<< "$out"; then ok; else ng "$1 (want '$2', exit $code)" "$out"; fi
}
expect_stop() { # NAME PATTERN
  if [[ $code -eq 2 ]] && grep -qF -- "$2" <<< "$out"; then ok; else ng "$1 (want stop with '$2', exit $code)" "$out"; fi
}

# --- work by location -------------------------------------------------------
mkproj "$HOME/work/app"
run "$HOME/work/app" ANTHROPIC_PROFILE=takt ANTHROPIC_API_KEY=sk-x OPENAI_API_KEY=sk-y \
  TAKT_OPENROUTER_API_KEY=or-z CLAUDE_CODE_USE_BEDROCK=1 -- run
expect_line "work: config dir" "TAKT_CONFIG_DIR=$work_cfg"
expect_line "work: ANTHROPIC_PROFILE removed" "ANTHROPIC_PROFILE=<unset>"
expect_line "work: ANTHROPIC_API_KEY removed" "ANTHROPIC_API_KEY=<unset>"
expect_line "work: OPENAI_API_KEY removed" "OPENAI_API_KEY=<unset>"
expect_line "work: TAKT_*_API_KEY removed" "TAKT_OPENROUTER_API_KEY=<unset>"
expect_line "work: Bedrock switch removed" "CLAUDE_CODE_USE_BEDROCK=<unset>"
expect_line "work: empty Anthropic config dir" "ANTHROPIC_CONFIG_DIR=$work_cfg/anthropic-empty"
expect_line "work: OpenCode CLI disabled" "TAKT_OPENCODE_PATH=/usr/bin/false"
expect_line "work: args untouched" "ARGS=run"

mkproj "$HOME/work/marked" "billing=api"
run "$HOME/work/marked" -- run
expect_stop "work: private.conf under ~/work stops" "private settings in a work project"

mkproj "$HOME/work/oldauth"
echo "anthropic_profile=takt" > "$HOME/work/oldauth/.takt/auth.conf"
run "$HOME/work/oldauth" -- run
expect_stop "work: auth.conf under ~/work stops" "private settings in a work project"

mkproj "$HOME/elsewhere/tool"
run "$HOME/elsewhere/tool" -- list
expect_line "elsewhere: work" "TAKT_CONFIG_DIR=$work_cfg"

mkproj "$HOME/elsewhere/marked" "billing=api"
run "$HOME/elsewhere/marked" -- list
expect_stop "elsewhere: marker outside the private root stops" "private settings in a work project"

mkproj "$private_root/unmarked"
run "$private_root/unmarked" ANTHROPIC_PROFILE=takt -- run
expect_line "private root without marker: work" "TAKT_CONFIG_DIR=$work_cfg"
expect_line "private root without marker: no API profile" "ANTHROPIC_PROFILE=<unset>"

# --- private ------------------------------------------------------------------
mkproj "$private_root/site" "billing=api"
run "$private_root/site" -- run
expect_line "private api: config dir" "TAKT_CONFIG_DIR=$private_cfg"
expect_line "private api: profile" "ANTHROPIC_PROFILE=takt"
expect_line "private api: args untouched" "ARGS=run"
mkdir -p "$private_root/site/src"
run "$private_root/site/src" -- run
expect_line "private api: from a subdirectory" "TAKT_CONFIG_DIR=$private_cfg"

mkproj "$private_root/custom" "anthropic_profile=other"
run "$private_root/custom" -- run
expect_line "private: anthropic_profile key" "ANTHROPIC_PROFILE=other"

mkproj "$private_root/sub" "billing=subscription"
run "$private_root/sub" ANTHROPIC_PROFILE=takt ANTHROPIC_API_KEY=sk-x -- run
expect_line "private subscription: assignment" "ARGS=--runtime-assignment credit-out run"
expect_line "private subscription: no profile" "ANTHROPIC_PROFILE=<unset>"
expect_line "private subscription: no API key" "ANTHROPIC_API_KEY=<unset>"

run "$private_root/site" TAKT_BILLING=subscription -- list
expect_line "TAKT_BILLING overrides billing" "ARGS=--runtime-assignment credit-out list"

mkproj "$private_root/badkey" "billing=api
colour=blue"
run "$private_root/badkey" -- run
expect_stop "private: unknown key stops" "unknown key 'colour'"

mkproj "$private_root/badbilling" "billing=free"
run "$private_root/badbilling" -- run
expect_stop "private: bad billing stops" "billing must be api or subscription"

mkproj "$private_root/both" "billing=api"
echo "anthropic_profile=takt" > "$private_root/both/.takt/auth.conf"
run "$private_root/both" -- run
expect_stop "private: leftover auth.conf stops" "is replaced by .takt/private.conf"

mkdir -p "$private_root/nogit/.takt"
echo "billing=api" > "$private_root/nogit/.takt/private.conf"
run "$private_root/nogit" -- run
expect_line "private: outside git uses the cwd" "TAKT_CONFIG_DIR=$private_cfg"

# Linked worktree: the main checkout's marker counts, the location still decides.
git -C "$private_root/site" -c user.email=t@example.invalid -c user.name=t commit -q --allow-empty -m init
git -C "$private_root/site" worktree add -q "$private_root/worktrees/site-x" -b x
run "$private_root/worktrees/site-x" -- run
expect_line "private worktree: main checkout marker" "TAKT_CONFIG_DIR=$private_cfg"
git -C "$private_root/site" worktree add -q "$HOME/work/site-y" -b y
run "$HOME/work/site-y" -- run
expect_stop "worktree under ~/work of a private repo stops" "private settings in a work project"

# Symlink from the private root into ~/work: the resolved location decides.
mkproj "$HOME/work/linked"
ln -s "$HOME/work/linked" "$private_root/linked"
echo "billing=api" > "$HOME/work/linked/.takt/private.conf"
run "$private_root/linked" -- run
expect_stop "symlink into ~/work stops" "private settings in a work project"
rm "$HOME/work/linked/.takt/private.conf"
run "$private_root/linked" -- run
expect_line "symlink into ~/work without marker: work" "TAKT_CONFIG_DIR=$work_cfg"

# --- work: mixed settings -----------------------------------------------------
run "$HOME/work/app" TAKT_CONFIG_DIR="$private_cfg" -- run
expect_stop "work: inherited private config dir stops" "TAKT_CONFIG_DIR is the private config"
run "$HOME/work/app" TAKT_CONFIG_DIR="$tmp/other" -- run
expect_line "work: other inherited config dir is replaced" "TAKT_CONFIG_DIR=$work_cfg"

printf 'provider:\n  profiles:\n    x: {provider: opencode, model: opencode-go/kimi}\n' > "$HOME/work/app/.takt/runtime.yaml"
run "$HOME/work/app" -- run
expect_stop "work: opencode in project runtime.yaml stops" "runtime.yaml"
printf 'provider:\n  assignments:\n    a: {}\n' > "$HOME/work/app/.takt/runtime.yaml"
run "$HOME/work/app" -- run
expect_stop "work: assignments in project runtime.yaml stops" "assignments"
printf '# no opencode here, only Codex\nprovider:\n  defaults: {profile: c}\n' > "$HOME/work/app/.takt/runtime.yaml"
run "$HOME/work/app" -- run
expect_line "work: a comment mentioning opencode is fine" "TAKT_CONFIG_DIR=$work_cfg"
rm "$HOME/work/app/.takt/runtime.yaml"
printf 'anthropic_api_key: sk-x\n' > "$HOME/work/app/.takt/config.yaml"
run "$HOME/work/app" -- run
expect_stop "work: API key in project config.yaml stops" "config.yaml"
rm "$HOME/work/app/.takt/config.yaml"

mkdir -p "$work_cfg"
printf 'rate_limit_fallback:\n  switch_chain:\n    - provider: opencode\n' > "$work_cfg/config.yaml"
run "$HOME/work/app" -- run
expect_stop "work: opencode in ~/.takt-work stops" "$work_cfg/config.yaml"
rm "$work_cfg/config.yaml"

for args in "--provider opencode" "--provider=opencode" "--model opencode-go/kimi-k3.1-pro" \
  "--model=openrouter/x/y" "--runtime-assignment credit-out" "--runtime-file x.yaml"; do
  # shellcheck disable=SC2086
  run "$HOME/work/app" -- $args run
  expect_stop "work: '$args' stops" "not allowed in work projects"
done
run "$HOME/work/app" -- -t "compare opencode with codex" run
expect_line "work: task text mentioning opencode is fine" "TAKT_CONFIG_DIR=$work_cfg"

touch "$work_cfg/anthropic-empty/active_config"
run "$HOME/work/app" -- run
expect_stop "work: non-empty Anthropic config dir stops" "must stay empty"
rm "$work_cfg/anthropic-empty/active_config"

printf '%d passed, %d failed (%s)\n' "$pass" "$fail" "$("$test_bash" -c 'echo $BASH_VERSION')"
[[ $fail -eq 0 ]]
