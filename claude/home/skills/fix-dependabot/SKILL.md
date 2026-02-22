---
name: fix-dependabot
description: Dependabot セキュリティアラートを自動修正し、リポジトリごとに PR を作成する
user-invokable: true
---

## 指示

自分がオーナーの全リポジトリから Dependabot セキュリティアラートを取得し、自動で修正 PR を作成する。確認なしの完全自動処理で、アラート検出から修正・PR 作成まで一気通貫で行う。

---

## Step 1: 認証確認・リポジトリ一覧取得

1. `gh auth status` で GitHub CLI の認証状態を確認する
   - 未認証の場合は `gh auth login` を案内して **中断** する
2. 全リポジトリを取得する:
   ```bash
   gh repo list --limit 1000 --json nameWithOwner,defaultBranchRef --no-archived
   ```

---

## Step 2: Dependabot アラートの一括取得

各リポジトリについて、open 状態の Dependabot アラートを取得する:

```bash
gh api /repos/{owner}/{repo}/dependabot/alerts --jq '[.[] | select(.state=="open")]'
```

- アラート 0 件のリポジトリはスキップ
- アラートがあるリポジトリとアラート数をログ出力する

---

## Step 3: リポジトリごとの並列修正

アラートのあるリポジトリごとに Task ツール（`subagent_type: general-purpose`）を起動して **並列処理** する。

### サブエージェントに渡す情報

- リポジトリ名（owner/repo）
- デフォルトブランチ名
- アラートの詳細リスト（アラート番号、パッケージ名、現在バージョン、修正バージョン、エコシステム、severity、URL）
- 作業ディレクトリのパス（スキル実行時のカレントディレクトリ）

### サブエージェントの処理フロー（各リポジトリにつき 1 エージェント）

#### 1. ローカルリポジトリの準備

- 作業ディレクトリ配下にリポジトリ名のディレクトリが存在するか確認
- なければ `gh repo clone {owner}/{repo}`
- `git switch {default_branch}` でデフォルトブランチに切り替え
- `git pull` で最新化

#### 2. アラートごとの修正（アラートを順次処理）

**a. ブランチ作成:**
- ブランチ名: `fix/dependabot-{alert_number}-{package_name}`
- `git switch {default_branch}` でデフォルトブランチに戻る
- `git switch -c {branch_name}` で作業ブランチ作成

**b. 依存関係の更新（エコシステムに応じて）:**
- **npm**: `npm install {package}@{fixed_version}`
- **pip**: `requirements.txt` / `pyproject.toml` 等のバージョンを編集し `pip install -r requirements.txt` 等
- **cargo**: `cargo update -p {package}`
- **gomod**: `go get {package}@{fixed_version} && go mod tidy`
- **bundler**: `bundle update {gem}`
- **composer**: `composer require {package}:{fixed_version}`
- **maven**: `pom.xml` のバージョンを直接編集
- **nuget**: `dotnet add package {package} --version {fixed_version}`
- エコシステムが不明な場合: マニフェストファイルを特定して該当パッケージのバージョンを直接編集

**c. コミット・プッシュ:**
```bash
git add .
git commit -m "fix: update {package} to {fixed_version} (dependabot alert #{number})"
git push -u origin {branch_name}
```

**d. PR 作成:**
```bash
gh pr create \
  --title "fix: update {package} to {fixed_version}" \
  --body "$(cat <<'EOF'
## Summary
- Fixes Dependabot alert #{number}
- Updates {package} from {current_version} to {fixed_version}
- Severity: {severity}

## Dependabot Alert
{alert_url}
EOF
)" \
  --repo {owner}/{repo}
```

**e. エラー時:**
- ブランチを削除する: `git switch {default_branch} && git branch -D {branch_name}`
- スキップして次のアラートへ進む
- 結果に「失敗」と理由を記録する

#### 3. 結果を返却

各アラートの対応結果（成功/失敗、PR URL）をまとめて返す。

---

## Step 4: 結果レポート

全サブエージェントの完了後、結果をまとめてテーブル形式で表示する:

| リポジトリ | アラート # | パッケージ | 対応結果 | PR URL |
|-----------|-----------|-----------|---------|--------|
| owner/repo | #123 | lodash | 成功 | URL |
| owner/repo | #456 | express | 失敗（理由） | - |
