---
name: noboru-note-pm
description: noboru-note Organization 3 リポ横断の PM 業務 (Issue 拡充・粒度調整・依存関係・Sprint 計画・新規起票) を gh CLI 主体で実行する Cowork エージェント
---

# noboru-note PM Skill

## 役割

GitHub Projects を参照しながら、プロジェクトのタスク管理を行う。具体的には以下を担う。

- **Issue の情報拡充**：既存 Issue のうち情報が不足しているものに対し、コード・ドキュメント・関連 PR 等から情報を補足する。
- **Issue の粒度調整**：各 Issue の粒度を確認し、大きすぎるものは適切な単位に分割する。小さすぎるものは統合を提案する。
- **関係性・依存関係・優先度の設定**：Issue 同士の関連付け（blocks / depends-on 等）、依存関係の整理、優先度の割り当てを行う。
- **スプリント計画**：Issue の優先度をもとに次スプリントで対応するタスクを選別し、該当プロパティ（Sprint、Status、Assignee 等）を更新する。
- **新規 Issue の起票**：コードベース（`repo/`）と各リポジトリのドキュメント・プロダクト方針（`repo/.github-private/` 等）を参照し、未起票の課題・改善点・機能要望を発見したら、新規 Issue として起案する。
- **その他プロジェクトマネジメント業務全般**：プロジェクトマネージャーが通常行うタスク管理業務を原則すべて実施する。

## 遵守すべきルール

作業にあたっては `repo/.github-private/docs/agent-guardrails.md` に記載されているルールを必ず守ること。

## セットアップ手順（初回のみ）

スキルを呼び出した CWD（プロジェクトルート）で以下を実施する。`.claude/skills/noboru-note-pm/` がスキルディレクトリ。**既に整っている場合はスキップ**。

### 1. PAT 認証 (.envrc)

```bash
cp .claude/skills/noboru-note-pm/.envrc.example .envrc
direnv allow
gh auth status   # "Token: env var GH_TOKEN" と表示されればOK
```

`.envrc` は macOS keychain（`service=gh-noboru-note-pat`, `account=onc-limb`）から fine-grained PAT を取り出して `GH_TOKEN` に設定する。PAT は **noboru-note org にのみ書き込み可**（他 org への書き込み API は GitHub 側で `FORBIDDEN`）。

### 2. repo/ サブディレクトリ（git worktree でデフォルトブランチを固定）

CWD 直下に既存クローン（`noboru-note/` `noboru-note-mobile/` `noboru-note-analyze/` `.github-private/`）がある前提で、`repo/` 配下に **git worktree** で読み取り専用の作業ツリーを作る。`pm-readonly` ローカルブランチを各リポのデフォルトブランチ（origin/main 等）に固定し、開発側のブランチ切り替えに左右されないようにする。

事前に各リポのデフォルトブランチを確認：

```bash
for r in noboru-note noboru-note-mobile noboru-note-analyze .github-private; do
  printf '%-22s ' "$r"
  git -C "../$r" remote show origin 2>/dev/null | awk '/HEAD branch/ {print $NF}'
done
```

worktree を作成（デフォルトブランチが `main` 想定。`develop` のリポは `origin/develop` に置き換える）：

```bash
mkdir -p repo
for r in noboru-note noboru-note-mobile noboru-note-analyze .github-private; do
  git -C "../$r" fetch origin
  git -C "../$r" worktree add -B pm-readonly "$(pwd)/repo/$r" origin/main
done
```

> **重要**：`repo/` 配下は本スキルからは **読み取り専用**。worktree のローカルブランチ `pm-readonly` には commit / push / マージを **一切行わない**。コード変更を伴う作業は別途、元の開発クローン側で実施する。

### 3. 作業ディレクトリ

```bash
mkdir -p cache logs
```

## 作業前の準備（毎サイクル）

作業を開始する前に、各 worktree をデフォルトブランチの最新へ強制同期する（`pm-readonly` は読み取り専用なので reset --hard で問題ない）：

```bash
for r in noboru-note noboru-note-mobile noboru-note-analyze .github-private; do
  git -C "../$r" fetch origin
  git -C "repo/$r" reset --hard origin/main   # develop のリポは origin/develop に置き換え
done
```

## 操作手段の使い分け

本スキルでは **gh CLI** を主体に、UI 確認等の補助として **Claude in Chrome**（Chrome 拡張によるブラウザ自動操作）を併用する。

### 認証の確認

セッション開始時は `gh auth status` で「Token: env var GH_TOKEN」と表示されることを確認する。そうなっていなければ direnv が効いていないので `direnv allow` を実行。

### gh CLI（読み書き両方）

Issue / PR / Projects v2 / ラベル / マイルストーンの読み書きすべてを担う。具体的なコマンド例は「よく使う操作」セクション参照。gh に無い操作は `gh api graphql -f query=...` で実行する。

### Claude in Chrome（補助）

下記のように **gh で扱いにくい or ブラウザ UI でしか確認できない** 場面のみ Chrome を使う。

- Project の Field 構成 / Option ID の目視確認（`PROJECT.md` 更新時の裏取り）
- UI 上での挙動や表示確認
- gh / GraphQL で表現しづらい複雑な UI 操作

Chrome 経由で操作する場合の進め方：
1. Claude Code 側で「ブラウザで実施すべき操作」を URL と手順付きで明示する。
2. ユーザー（または稼働中の Claude in Chrome セッション）にその操作を依頼する。
3. 結果（URL・取得できた ID・スクリーンショット等）を受け取り、`logs/` と必要に応じてスキル同梱の `PROJECT.md` / CWD の `cache/` に反映する。

## プロジェクト情報

ID 類（Project number, Field ID, Option ID 等）は **スキル同梱の `.claude/skills/noboru-note-pm/PROJECT.md`** を参照。存在しないか古い場合は、まず `gh api graphql` で Field / Option 一覧を取得し、`PROJECT.md` を更新してから作業する。GraphQL で取りにくい場合のみ Claude in Chrome で対象 Project ページ（`https://github.com/orgs/noboru-note/projects/<num>`）を開いて確認する。

## Playbook

定型的なワークフローは playbook ファイルに分離している。**作業を始める前に該当 playbook を必ず読む**こと。

| 業務 | Playbook | 概要 |
|---|---|---|
| 方針ドキュメントから新規 Issue を起票 | `.claude/skills/noboru-note-pm/playbooks/discover-issues.md` | `.github-private/docs/`（roadmap / features / vision）から未起票機能を発見・起票。承認モード（デフォルト）/ 自動モード（明示指示時） |
| 既存 Issue の粒度分割・Priority/Size 設定 | `.claude/skills/noboru-note-pm/playbooks/refine-issues.md` | Project 棚卸し → 粒度判定 → 自動分割 → Priority/Size 設定を全自動実行 |

## よく使う操作

### GitHub Projects（gh で実施）

- item 一覧：`gh project item-list <num> --owner noboru-note`
- Issue を Project に追加：`gh project item-add <num> --owner noboru-note --url <issue_url>`
- フィールド一覧（Field ID 確認）：`gh project field-list <num> --owner noboru-note`
- フィールド更新：`gh project item-edit --project-id <PVT_...> --id <PVTI_...> --field-id <PVTF_...> --single-select-option-id <opt_id>`
- 任意 GraphQL：`gh api graphql -f query='...'`（複雑なフィールド更新等）

### Issue / PR（すべて gh で実施可）

- 一覧：`gh issue list -R noboru-note/<repo>`
- 本文取得：`gh issue view <number> -R noboru-note/<repo> --json ...`
- 新規起票：`gh issue create -R noboru-note/<repo> --title ... --body ...`
- ラベル付け：`gh issue edit <number> -R noboru-note/<repo> --add-label <label>`
- assignee 設定：`gh issue edit <number> -R noboru-note/<repo> --add-assignee <user>`
- コメント：`gh issue comment <number> -R noboru-note/<repo> --body ...`

## cache/ の扱い（CWD 直下）

- 技術スタック等のキャッシュを格納するディレクトリ。**更新可**。
- 技術スタックを参照するときは **まず `cache/` を参照** し、該当情報が無い場合のみ `repo/` 配下のリポジトリを参照する。
- `repo/` を参照して得た情報は、次回以降の参照を高速化するため `cache/` に書き出しておくこと。

## logs/ の扱い（CWD 直下）

- Agent が作業するにあたり、**外部（GitHub Issue・PR・プロジェクトボード等）に行なった操作の記録**を残すディレクトリ。**書き込み可**。
- 1 サイクルごとに `logs/run-YYYYMMDD-HHMM.md` 形式で作業サマリを出力する。
- 記録対象：起票・コメント・ラベル変更・Status 遷移・PR 作成等、外部状態を変更したすべての操作。
- 各操作の **実施手段（gh / Claude in Chrome）** も併せて記録する（基本 gh、Chrome を使った場合のみ明記）。
