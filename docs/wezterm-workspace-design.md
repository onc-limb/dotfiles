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
┌──────────┬───────────────────────────────┬ ① Claude ───────────┐
│ neo-tree │ [app.ts] [ Terminal]          │ ● 作業中      30秒前 │
│          │  nvim (ファイル / ターミナル)  │ README を直して…     │
│          │                               │ ▸ Edit README.md     │
│          │                               ├ ② Codex ────────────┤
│          │                               │ ● 入力待ち     3分前 │
└──────────┴───────────────────────────────┴──────────────────────┘
 ◆ default │ 1 ◆ agents  2 repo  main  3 repo  feat-a │ ①claude ⏳ ②codex 💬 │ Opus 42% │ C 5h 32% 14:30 週 18% 水 09:00 │ X 週 23% 木 07:58
```

入れ子は ワークスペース → 作業環境 (タブ = ディレクトリ / worktree) → エージェント。

- 作業環境のタブは、左に nvim (ツリー・ファイル・ターミナル。ターミナルは真ん中で切り替える `nvim/lua/workbench.lua`)、
  右にエージェントの状態カード (`agent-dashboard --sidebar`、幅 34 セル)。カードはエージェントの数で高さを等分し、
  状態・最後に頼んだこと・いま使っているツールだけを出す。エージェントがいない間はカードの列ごと出さない
- エージェント本体は見えないワークスペース (`_agents`) で動かし、カードの Enter / クリック、`Cmd+a`、LEADER `1..9`、
  LEADER `z` で作業環境のタブに移して全画面で表示する。LEADER `z` / `Cmd+e` で見えないワークスペースに戻す
  (`bin/agent-view`)。WezTerm はアクティブでないワークスペースのウィンドウを表示しない
- エージェントは nvim の中では動かさない (nvim のターミナルの中ではキーが全部エージェントに届き、nvim のキーが効かない)

- LEADER `w` でワークスペースを選ぶと、作業環境の数とエージェントの状態が並び、入るとエージェント一覧タブが開く
- エージェント一覧タブは作業環境ごとのカードにエージェントを並べる（`a` でエージェントだけの待ち順一覧に切り替え）。
  j/k・h/l で選んで Enter かクリックで、その作業環境 (nvim) へ移動する / エージェントを全画面で表示する。
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

- どちらもリセット時刻 (`resets_at`) を一緒に保存し、タブバーには `14:30`（5 時間枠）/ `水 09:00`（週次）で出す
- Claude: ステータスラインが受け取る `rate_limits` を `~/.local/state/agents/quota-claude-<profile>.json` に書き出す
- Codex: セッションログ（`$CODEX_HOME/sessions/**/rollout-*.jsonl`）の最新の `token_count` から読む。
  今のアカウントでは週次（`window_minutes: 10080`）しか記録されていないので、ある枠だけ表示する
- 今いるワークスペースのアカウント（work / private）の値を表示する。古い値は薄く表示する

## 復旧

- 保存: タブ・ワークスペース・エージェントが変化したときと、タブバーの更新のついでに `session.json` へ書く
- 復元: WezTerm の起動時（`gui-startup`）だけ。新しいウィンドウを開いたときには復元しない
- エージェント: `claude --resume <id>` / `codex resume <id>`（`claude-auto` / `codex-auto` 経由）。
  見えないワークスペースで再開し、元のタブの状態カードに並べる (見えないワークスペース自体は保存しない)
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
| LEADER `b` | ライト / ダークの切り替え |
| LEADER `w` / LEADER `W` | ワークスペースの選択（入るとエージェント一覧タブ） / 作成 |
| LEADER `n` | worktree のタブを作る / 開く |
| LEADER `c` / LEADER `x` | Claude / Codex を起動して全画面で表示（右に状態カードが出る） |
| LEADER `z` | エージェントを表示する / 戻す（最後に見たエージェント。エージェントのいないタブではペインの拡大） |
| `Cmd+e` | ファイルへ（エージェントを見ていたら戻す） |
| `Cmd+a` | 次のエージェントを全画面で表示 |
| LEADER `1..9` | 番号のエージェントを表示（カードの ① ② と同じ番号） |
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

- フォント: SF Mono 14pt / 太さ 500（Orca と同じ）。Terminal.app 同梱のフォントを `font_dirs` で読む。
  アイコンは Symbols Nerd Font Mono で補う
- 配色: `wezterm/palette.lua` にライト (`M.light`) とダーク (`M.dark`) を並べ、WezTerm・nvim・エージェント一覧タブ・
  状態カードがすべて同じファイルから読む。ターミナルらしさを抑えた、少しレトロなデスクトップアプリ風の色合い:
  ライトは古い紙のクリーム色、ダークは焦げ茶がかった炭色を地に、ティール・からし色・れんが色・オリーブを差す。
  nvim は vscode.nvim の色を `palette.nvim` で上書きする（構文の色も同じ差し色）
- ライト / ダーク: LEADER `b` で切り替え、`~/.local/state/wezterm/theme` に保存する。WezTerm は設定を読み直し、
  nvim はこのファイルの変化を見て (`vim.uv.new_fs_event`) colorscheme を当て直し、一覧タブ・状態カードは再描画のたびに読む
- 背景: 透過させずに `bg` で塗りつぶす。タブバーと nvim のツリーは一段沈んだ `chrome` にし、
  アクティブなタブは本文と同じ色の札にする（アプリのタブ列のように）。ウィンドウの内側に余白を取る

## 実装メモ

- エージェントの出し入れは `wezterm cli split-pane --move-pane-id`（タブへ）と
  `move-pane-to-new-tab --new-window --workspace _agents`（見えないワークスペースへ）。Lua にはペインを
  別のタブへ移す API がないので、`bin/agent-view` が CLI で行い、WezTerm・カード・一覧タブから呼ぶ
- 作業環境の nvim は `~/.local/state/nvim/workbench/<WEZTERM_PANE>.sock` で待ち受け、WezTerm は
  `nvim --server <sock> --remote-expr "v:lua.require'workbench'.rpc(...)"` で真ん中のファイル・ターミナルを切り替える
- WezTerm 20240203 は、コマンド付きで `spawn_tab` / `split` すると `cwd` を無視して今のペインの
  ディレクトリで起動する。そのためコマンドの先頭で `cd` している（`workspace.lua` の `M.zsh`）
- Claude のセッションは起動したディレクトリに紐づくので、状態ファイルの `cwd` は起動時の値
  （SessionStart の hook とステータスラインの `project_dir`）だけを記録する
- 復旧は `WEZTERM_SESSION_FILE=<テスト用 json> wezterm start --always-new-process` で
  別プロセスの WezTerm を立てて試せる（動いている WezTerm の状態ファイルは消さない）
- Codex の hook は `~/.codex/hooks.json`（dotfiles 外）に登録している。仕事用の設定へは
  `bin/orca-hooks-sync` で Orca の hook と一緒にコピーする

## ファイル

| ファイル | 役割 |
|---|---|
| `bin/agent-state` | hook / ステータスラインから状態ファイルと利用制限を書く |
| `bin/agent-dashboard` | エージェント一覧タブの中身 / `--sidebar` で作業環境の右の状態カード |
| `bin/agent-view` | エージェントをタブに出して全画面にする / 見えないワークスペースに戻す |
| `wezterm/palette.lua` | 配色（nvim・エージェント一覧タブからも読む） |
| `wezterm/theme.lua` | ライト / ダークの切り替えと背景 |
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
