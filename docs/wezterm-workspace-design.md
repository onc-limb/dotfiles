# WezTerm ワークスペース設計

Orca から WezTerm に一本化するための設計メモ。herdr は使わず、WezTerm + nvim + Claude Code / Codex の hook だけで組む。

## 前提

- 業務は WezTerm 1 つで完結させる（ブラウザだけは別アプリ。AeroSpace で並べる）
- 操作はキーボードだけで完結させる
- 見た目が多少理想と違っても、情報量が同じなら実装がシンプルな方を選ぶ
- WezTerm を閉じたあとにエージェントを動かし続ける必要はない（mux サーバーは使わない）。
  代わりに、再起動時にワークスペース・タブ・nvim のファイル・エージェントのセッションを復旧する

## 画面構成

```
ファイルを開いているとき                          ファイルを開いていないとき
┌──────────┬────────────────────┬──────────────┐  ┌──────────┬─────────────────────────────────┐
│ neo-tree │ [app.ts] [Terminal]│ ① Claude Code│  │ neo-tree │ ① Claude Code                   │
│          │  nvim (ファイル /   │ (そのまま    │  │          │ (エージェントの列を広く)        │
│          │   ターミナル)       ├──────────────┤  │          ├─────────────────────────────────┤
│          │                    │ ② Codex      │  │          │ ② Codex                         │
└──────────┴────────────────────┴──────────────┘  └──────────┴─────────────────────────────────┘
 ◆ default │ 1 ◆ agents  2 repo  main  3 repo  feat-a │ ①claude ⏳ ②codex 💬 │ Opus 42% │ C 5h 32% 14:30 w 18% Wed 09:00 │ X w 23% Thu 07:58
```

入れ子は ワークスペース → 作業環境 (タブ = ディレクトリ / worktree) → エージェント。

- 作業環境のタブは、左に nvim (ツリー・ファイル・ターミナル。ターミナルは真ん中で切り替える `nvim/lua/workbench.lua`)、
  右にそのタブのエージェントを縦に積んだ列を、拡大せずにそのまま操作できる形で出す。列の順はタブバーの ① ② と同じで、
  高さは等分する。nvim の起動時にターミナルは開かない
- 幅は nvim の状態に合わせる: nvim はファイル (かターミナル) を開いているかを user var `workbench_layout`
  (`edit` / `tree`) で知らせ、WezTerm (`workspace.apply_layout`) が `edit` ならエージェントの列を全体の 30% (最低 40 セル)、
  `tree` なら nvim をツリーの幅 (34 セル) まで縮めて残りを列にする。あわせて列の高さを等分する。合わせるのは
  状態・列のエージェント・ウィンドウの大きさが変わったときだけで、手で変えた大きさは戻さない。`Cmd+Shift+a` で、ファイルを開いていても
  `tree` と同じ幅 (ツリーだけ残して列を広く) にする / 戻す (タブごと)
- LEADER `c` / `x` で起動したエージェントは列の一番下に積む。`Cmd+a`、LEADER `1..9`、一覧タブの Enter / クリックで
  列のエージェントに移る。LEADER `z` で列ごと見えないワークスペース (`_agents`) に隠す / 出す (`bin/agent-view`)。
  WezTerm はアクティブでないワークスペースのウィンドウを表示しない。隠していなければ、復旧したタブなどで列に
  そろっていないエージェントは自動で積む (`workspace.ensure_agent_shown`)
- エージェントは nvim の中では動かさない (nvim のターミナルの中ではキーが全部エージェントに届き、nvim のキーが効かない)

- LEADER `w` でワークスペースを選ぶと、作業環境の数とエージェントの状態が並び、入るとエージェント一覧タブが開く
- エージェント一覧タブは作業環境ごとのカードにエージェントを並べる（`a` でエージェントだけの待ち順一覧に切り替え）。
  j/k・h/l で選んで Enter かクリックで、その作業環境 (nvim) へ移動する / エージェントをその作業環境の右の列に出す。
  利用制限はメーターとリセット時刻・残り時間で出す。配色は `palette.lua` を読み、背景は塗らずにペインの背景色のまま
- 起動時は、エージェント一覧タブのほかに作業環境のタブを最低 1 つ開く（復元するタブがなければホームで開く）

- タブバーは下に 1 本だけ (WezTerm のタブバーは 1 行固定で、2 段にはできない)。
  左端にワークスペース名、続けて worktree のタブ (リポジトリ名とブランチ)、右にエージェントの状態と利用制限を出す。
  ディレクトリはタブ名でわかるので、WezTerm の中では Claude のステータスラインからディレクトリの行を省く
- タブ = worktree。ワークスペース = private / work / 案件
- 作業環境のタブ名は「リポジトリ名  ブランチ」(worktree でも元のリポジトリ名)。git の外ならディレクトリ名。
  エージェント一覧タブのカードも同じ名前にする
- ワークスペースごとに、閉じられないエージェント一覧タブ（◆）を 1 つ置く
- エージェントがどのタブのものかは、状態ファイルの `home`（所属するペイン = 作業環境のメインの nvim、
  または一覧タブ）で決める。ペインで直接 `claude` を動かした場合 (home なし) は、そのペインのタブのもの
- タブを閉じるときは、そのタブのエージェントも止めるか確認する。所属するペインが無くなったエージェントは止める

## データの流れ

```
Claude / Codex の hook ──┐
Claude のステータスライン ─┼─▶ ~/.local/state/agents/<WEZTERM_PANE>.json ──▶ WezTerm (タブバー)
Codex のセッションログ ───┘   状態 / session_id / モデル / コンテキスト /       │
                              頼んだこと / いまのツール / home                  │
                                                                         ▼
WezTerm (タブ・ワークスペースの変化) ──▶ ~/.local/state/wezterm/session.json ──▶ 起動時に復旧
```

エージェントの状態ファイルに session_id も入れ、タブバーと復旧で同じデータを使う。
WezTerm は読むだけ、エージェント側は書くだけ。

### エージェントの状態

| 状態 | Claude の hook | Codex の hook |
|---|---|---|
| working ⏳ | UserPromptSubmit / PreToolUse | UserPromptSubmit / PreToolUse |
| waiting 💬 | Notification / PermissionRequest | PermissionRequest |
| done ✅ | Stop | Stop |
| (削除) | SessionEnd | SessionEnd |

状態ファイルの例:

```json
{ "tool": "claude", "profile": "work", "session_id": "…", "cwd": "/…/repo-feat-a",
  "state": "working", "model": "Opus", "ctx_pct": 42, "updated_at": 1794000000,
  "pane": 12, "home": 3, "task": "README を直して…", "activity": "Edit README.md" }
```

- `task`: UserPromptSubmit の入力 (1 行に詰めて 200 文字まで)。再開したセッションは SessionStart で
  トランスクリプトから最後の入力を読む
- `activity`: PreToolUse のツール名と対象 (ファイル名・コマンドなど)。Stop と次の入力で消す
- `home`: エージェントを起動した WezTerm が `AGENT_HOME` で渡す

### 利用制限

- どちらもリセット時刻 (`resets_at`) を一緒に保存し、タブバーには `14:30`（5 時間枠）/ `Wed 09:00`（週次、ラベルは `w`）で出す
- Claude: ステータスラインが受け取る `rate_limits` を `~/.local/state/agents/quota-claude-<profile>.json` に書き出す
- Codex: セッションログ（`$CODEX_HOME/sessions/**/rollout-*.jsonl`）の最新の `token_count` から読む。
  今のアカウントでは週次（`window_minutes: 10080`）しか記録されていないので、ある枠だけ表示する
- 今いるワークスペースのアカウント（work / private）の値を表示する。古い値は薄く表示する

## 復旧

- 保存: タブ・ワークスペース・エージェントが変化したときと、タブバーの更新のついでに `session.json` へ書く
- 復元: WezTerm の起動時（`gui-startup`）だけ。新しいウィンドウを開いたときには復元しない
- エージェント: `claude --resume <id>` / `codex resume <id>`（`claude-auto` / `codex-auto` 経由）。
  見えないワークスペースで再開し、元のタブを開いたときに右の列に積む (見えないワークスペース自体は保存しない)
- nvim: worktree ごとに `:mksession` を `~/.local/state/nvim/sessions/` に保存し、起動時に読み込む
- 戻らないもの: 実行中だった処理、スクロール履歴、nvim の中のターミナル

## worktree

- 作る場所はリポジトリの隣: `<repo>-<branch>`（`/` は `-` に置き換える）
- 作成後、worktree のルートに `.worktree-init` があれば実行する

## キー

ペイン移動は LEADER(`Ctrl+Q`)+hjkl のまま、`Cmd+1..9` もタブ切り替えのまま。

| キー | 操作 |
|---|---|
| `Cmd+t` / `Cmd+Shift+t` | 今のディレクトリで作業環境のタブ (nvim + ツリー) / 素のシェルのタブ |
| `Cmd+0` | エージェント一覧タブへ |
| LEADER `b` / LEADER `Shift+b` | ライト / ダークの切り替え / 配色（パターン × ライト・ダークの 6 通り）を選ぶ |
| LEADER `w` / LEADER `W` | ワークスペースの選択（入るとエージェント一覧タブ） / 作成 |
| LEADER `n` | worktree のタブを作る / 開く |
| LEADER `c` / LEADER `x` | Claude / Codex を起動して右の列の一番下に積む（フォーカスも移す） |
| `Cmd+Shift+a` | ファイルを開いていても右のエージェントの列を広げる（ツリーだけ残す） / 戻す |
| LEADER `z` | 右のエージェントの列を隠す / 出す（出すと最後に見たエージェントへ。エージェントのいないタブではペインの拡大） |
| `Cmd+e` | nvim のファイルへ（右のエージェントはそのまま） |
| `Cmd+a` | 列の次のエージェントへ（nvim からは一番上へ） |
| LEADER `1..9` | 番号のエージェントへ（タブバーの ① ② と同じ番号） |
| `Cmd+j` / LEADER `t` | nvim の真ん中のターミナルとファイルを行き来 / 新しいターミナル |
| `Cmd+[` / `Cmd+]` | nvim の真ん中の左右のタブへ |
| LEADER `X` | ペインを閉じる（nvim では真ん中のファイル・ターミナルを閉じる。LEADER `x` は Codex） |
| `Cmd+w` | タブを閉じる（エージェントがいれば一緒に止めるか確認。エージェント一覧タブは閉じない） |

nvim 側:

| キー | 操作 |
|---|---|
| `Space e` | ツリーにフォーカス / ツリー上で閉じる |
| `Space E` | ツリーを変更ファイル表示に切り替え（ツリー上では `<` `>` でも切り替え、`D` で差分） |
| `Ctrl+/` | 真ん中のターミナルとファイルを行き来（`Cmd+j` と同じ） |
| `Space m` | Markdown のソース / レンダリング表示を切り替え |
| `Space gd` | 変更の一覧と差分（diffview） |

## 見た目

- フォント: 配色パターンごとに決める（Instrument は SF Mono、Aviation は JetBrains Mono、Thermal は Fira Code）。14pt で、
  ライトは Medium、ダークは一段細い Regular（暗い背景の明るい文字は太って滲んで見えやすい）。ヒンティングは弱め
  (`freetype_load_target = "Light"`、`freetype_load_flags = "NO_HINTING"`)。nvim とエージェントは WezTerm の中で動くので同じフォントになる。
  SF Mono は Terminal.app 同梱のフォントを `font_dirs` で読む。アイコンは Symbols Nerd Font Mono で補う
- 配色: `wezterm/palette.lua` に配色パターン (Instrument 計測器 / Aviation 航空計器 / Thermal サーモグラフィ) を
  ライト・ダークの組で並べる。
  各パターンは十数色だけ持ち、ANSI 色や nvim (vscode.nvim の `color_overrides`) の色はそこから計算する。
  既定は Thermal のライト
- 切り替え: LEADER `Shift+b` でパターン × ライト / ダークの 6 通りから選び、LEADER `b` でライト / ダークだけを切り替える。
  `~/.local/state/wezterm/scheme` / `theme` に保存し、WezTerm は設定を読み直す。nvim はこれらのファイルの変化を見て
  (`vim.uv.new_fs_event`) colorscheme を当て直す。一覧タブは WezTerm が書き出す
  `~/.local/state/wezterm/palette.json` を再描画のたびに読む
- Claude Code: WezTerm から起動するとき (`bin/agent-auto`) は `--settings '{"theme":"dark-ansi"}'`
  (ライトなら `light-ansi`) を付け、ターミナルの 16 色 (= palette.lua) で描かせる。settings.json は他の端末用に `auto` のまま。
  起動時のモードで決まるので、切り替える前から動いているセッションは元の色のまま
- カーソルと日本語の変換中の文字の下地は、差し色を背景に寄せて薄めた `cursor`
- 装飾: メインの画面 (nvim・カード) は簡素なまま、エージェント一覧タブとタブバーだけ色を使う。
  色はパターンの色を色相順に並べた `palette.deco`。アクティブなタブはタブの色 (紫系統) の札にし、
  右側の状態・モデル・利用制限は色の札にする。一覧タブは見出しをグラデーションの帯、作業環境のカードは
  タイトル行を色で塗り、状態は色の札、利用制限のメーターは緑 → 黄 → 赤のグラデーションにする。
  札はどれも、その色を背景に寄せた淡い地 (`tint`) に、同じ色相を文字の色に寄せた文字 (`ink`) で描く。
  濃い地に文字を載せない (ライトでもダークでも読める)
- ターミナルらしさを抑える工夫:
  - 背景は透過させずに `bg` で塗りつぶす。タブバーと nvim のツリーは一段沈んだ `chrome`、カードは一段浮いた `card`
  - タブバーは fancy 版にして、UI 用の可変幅フォント (Helvetica Neue / ヒラギノ) で描く。ワークスペース名は薄い文字
  - カードは罫線文字で囲まず、塗った面にする (選択中は左端にアクセント色の縦線)
  - ウィンドウの余白を広めに取り、行間を少し広げ、カーソルは縦線にする。
    下だけはタブバーと接するので余白なし。nvim はコマンド行を隠し (`cmdheight=0`)、一番下まで本文を使う

- nvim を WezTerm のシェルから `nvim` / `nvim <ディレクトリ>`（`v`）で開いたときも、作業環境と同じ画面
  (ツリー + 真ん中) にする（`workbench.from_shell`）。ペインの role を main にし、`<WEZTERM_PANE>.sock` で待ち受けるので、
  タブ名・`Cmd+e`・エージェントの所属先も作業環境のタブと同じになる。終了すると role を戻す。
  ファイルを指定した起動・git などから呼ばれるエディタ・nvim の中の nvim は対象外
- nvim のバッファのタブには × を出さない。閉じるのは `Space b d`（ウィンドウを残す snacks の bufdelete）

## 実装メモ

- エージェントの出し入れは `wezterm cli split-pane --move-pane-id`（タブへ）と
  `move-pane-to-new-tab --new-window --workspace _agents`（見えないワークスペースへ）。Lua にはペインを
  別のタブへ移す API がないので、`bin/agent-view` が CLI で行い、WezTerm・一覧タブから呼ぶ
- 列に積むときは一番下のエージェントを分割する。高さの等分は `workspace.apply_layout` が `adjust-pane-size` で行う。
  `adjust-pane-size` は `--pane-id` のペインではなくタブのアクティブなペインの境界を動かすので、
  上から順にエージェントをアクティブにして下の境界を動かし、最後にフォーカスを戻す
- 作業環境の nvim は `~/.local/state/nvim/workbench/<WEZTERM_PANE>.sock` で待ち受け、WezTerm は
  `nvim --server <sock> --remote-expr "v:lua.require'workbench'.rpc(...)"` で真ん中のファイル・ターミナルを切り替える
- WezTerm 20240203 は、コマンド付きで `spawn_tab` / `split` すると `cwd` を無視して今のペインの
  ディレクトリで起動する。そのためコマンドの先頭で `cd` している（`workspace.lua` の `M.zsh`）
- Claude のセッションは起動したディレクトリに紐づくので、状態ファイルの `cwd` は起動時の値
  （SessionStart の hook とステータスラインの `project_dir`）だけを記録する
- 復旧は `WEZTERM_SESSION_FILE=<テスト用 json> wezterm start --always-new-process` で
  別プロセスの WezTerm を立てて試せる（動いている WezTerm の状態ファイルは消さない）
- WezTerm の Lua の処理はメインスレッドで動く。重くなると描画も `wezterm cli` も止まり、一覧タブもエージェントの出し入れも固まる。
  次の 2 つを守る:
  - イベントごとに何度も呼ばれるフック (`format-tab-title`・`format-window-title` など) は使わない。
    `format-tab-title` はペインのタイトルが変わるたびに全タブ分呼ばれ、そのたびに設定全体を Lua に変換する。
    エージェントがタイトルを書き換え続けると CPU 100% で固まった (2026-11)。タブ名は `update-right-status` (毎秒) から
    `set_title` で書き込む (`tabs.refresh`)。元のタブ名は `workspace.tab_name` で読む (`get_title` は表示用の名前を返す)
  - 毎秒の `update-right-status` に処理を足すときは、外部コマンド (`run_child_process`) を毎回起動せずキャッシュする
  - 一覧タブは `wezterm cli list` の応答時間を測り、1 秒以上かかったらヘッダーの下に警告を出す。
    出たら `sample <wezterm-gui の pid> 3` でメインスレッドの中身を見る
- Claude Code はタイトルをスピナーで書き換え続けるので、`settings.json` の `CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1` で止めている
- Codex の hook は `~/.codex/hooks.json`（dotfiles 外）に登録している。仕事用の設定へは
  `bin/orca-hooks-sync` で Orca の hook と一緒にコピーする

## ファイル

| ファイル | 役割 |
|---|---|
| `bin/agent-state` | hook / ステータスラインから状態ファイルと利用制限を書く |
| `bin/agent-dashboard` | エージェント一覧タブの中身（`--sidebar` の状態カードは今は使っていない） |
| `bin/agent-view` | エージェントを作業環境の右の列に積む / 見えないワークスペースに戻す |
| `wezterm/palette.lua` | 配色パターン（nvim も読む） |
| `wezterm/theme.lua` | 配色パターン・ライト / ダークの切り替え、ウィンドウの見た目、palette.json の書き出し |
| `wezterm/statusbar.lua` | 下のタブバーの右側 |
| `wezterm/workspace.lua` | worktree タブ、エージェント、エージェント一覧タブ、キー操作 |
| `wezterm/session.lua` | 復旧の保存と復元 |
| `nvim/lua/worktree_session.lua` | worktree ごとに開いていたファイルの保存と復元 |
| `nvim/lua/workbench.lua` | nvim の真ん中のファイルとターミナルの切り替え |

## 実装の順番

1. 見た目（配色・フォント、nvim をそろえる）
2. nvim（neo-tree 常駐、中で開くターミナル、Markdown 切り替え、セッション保存）
3. エージェントの状態と利用制限（hook と状態ファイル、タブバー）
4. タブとワークスペース（worktree のタブ、エージェント起動、エージェント一覧タブ）。herdr と役割ペインを外す
5. 復旧
