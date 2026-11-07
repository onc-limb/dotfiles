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
┌──────────┬─────────────────────┬──────────────┐
│ neo-tree │ nvim (メイン)        │ エージェント   │
│ (表示切替)│ ターミナルも nvim 内 │ (縦に並べる)   │
└──────────┴─────────────────────┴──────────────┘
 1 feat-a  2 fix-b  ◆ agents │ ①claude ⏳ ②codex 💬 │ Opus 42% │ C 5h32% 週18% │ X 週23%
```

- タブバーは下に 1 本だけ。左に worktree のタブ、右にエージェントの状態と利用制限を出す
- タブ = worktree。ワークスペース = private / work / 案件
- ワークスペースごとに、閉じられないエージェント一覧タブ（◆）を 1 つ置く
- エージェントは右側に縦に並べるだけにする（裏に退避して入れ替える仕組みは作らない）

## データの流れ

```
Claude / Codex の hook ──┐
Claude のステータスライン ─┼─▶ ~/.local/state/agents/<WEZTERM_PANE>.json ──▶ WezTerm (タブバー)
Codex のセッションログ ───┘   状態 / session_id / モデル / コンテキスト        │
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
  "state": "working", "model": "Opus", "ctx_pct": 42, "updated_at": 1794000000 }
```

### 利用制限

- Claude: ステータスラインが受け取る `rate_limits` を `~/.local/state/agents/quota-claude-<profile>.json` に書き出す
- Codex: セッションログ（`$CODEX_HOME/sessions/**/rollout-*.jsonl`）の最新の `token_count` から読む。
  今のアカウントでは週次（`window_minutes: 10080`）しか記録されていないので、ある枠だけ表示する
- 今いるワークスペースのアカウント（work / private）の値を表示する。古い値は薄く表示する

## 復旧

- 保存: タブ・ワークスペース・エージェントが変化したときと、タブバーの更新のついでに `session.json` へ書く
- 復元: WezTerm の起動時（`gui-startup`）だけ。新しいウィンドウを開いたときには復元しない
- エージェント: `claude --resume <id>` / `codex resume <id>`（`claude-auto` / `codex-auto` 経由）
- nvim: worktree ごとに `:mksession` を `~/.local/state/nvim/sessions/` に保存し、起動時に読み込む
- 戻らないもの: 実行中だった処理、スクロール履歴、nvim の中のターミナル

## worktree

- 作る場所はリポジトリの隣: `<repo>-<branch>`（`/` は `-` に置き換える）
- 作成後、worktree のルートに `.worktree-init` があれば実行する

## キー

ペイン移動は LEADER(`Ctrl+Q`)+hjkl のまま、`Cmd+1..9` もタブ切り替えのまま。

| キー | 操作 |
|---|---|
| `Cmd+0` | エージェント一覧タブへ |
| LEADER `w` / LEADER `W` | ワークスペースの選択 / 作成 |
| LEADER `n` | worktree のタブを作る / 開く |
| LEADER `c` / LEADER `x` | Claude / Codex を起動 |
| `Cmd+e` | nvim のペインへ |
| `Cmd+a` | エージェントのペインへ（押すたびに次へ） |
| LEADER `1..9` | 番号でエージェントを選ぶ |
| LEADER `X` | ペインを閉じる（LEADER `x` は Codex に付け替えた） |
| `Cmd+w` | タブを閉じる（エージェント一覧タブは閉じない） |

nvim 側:

| キー | 操作 |
|---|---|
| `Space e` | ツリーにフォーカス / ツリー上で閉じる |
| `Space E` | ツリーを変更ファイル表示に切り替え（ツリー上では `<` `>` でも切り替え、`D` で差分） |
| `Ctrl+/` | nvim の中のターミナルを開閉 |
| `Space m` | Markdown のソース / レンダリング表示を切り替え |
| `Space gd` | 変更の一覧と差分（diffview） |

## 見た目

- フォント: SF Mono 14pt / 太さ 500（Orca と同じ）。Terminal.app 同梱のフォントを `font_dirs` で読む。
  アイコンは Symbols Nerd Font Mono で補う
- 配色: `wezterm/palette.lua` に集約し、WezTerm と nvim の両方から読む。ライト系で文字は濃いめ
- 背景: 透過 + ぼかし。nvim は背景を描画しない

## 実装メモ

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
| `bin/agent-dashboard` | エージェント一覧タブの中身 |
| `wezterm/palette.lua` | 配色（nvim からも読む） |
| `wezterm/statusbar.lua` | 下のタブバーの右側 |
| `wezterm/workspace.lua` | worktree タブ、エージェント、エージェント一覧タブ、キー操作 |
| `wezterm/session.lua` | 復旧の保存と復元 |
| `nvim/lua/worktree_session.lua` | worktree ごとに開いていたファイルの保存と復元 |

## 実装の順番

1. 見た目（配色・フォント・透過、nvim をそろえる）
2. nvim（neo-tree 常駐、中で開くターミナル、Markdown 切り替え、セッション保存）
3. エージェントの状態と利用制限（hook と状態ファイル、タブバー）
4. タブとワークスペース（worktree のタブ、エージェント起動、エージェント一覧タブ）。herdr と役割ペインを外す
5. 復旧
