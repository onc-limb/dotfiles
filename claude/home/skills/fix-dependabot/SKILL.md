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

アラートのあるリポジトリごとに Task ツール（`subagent_type: general-purpose`）を **`run_in_background: true`** で起動して **バックグラウンド並列処理** する。

**重要: メインセッションの役割は Step 1, 2, 4 のみ。実際の修正作業はすべてサブエージェントに委譲する。メインセッションでリポジトリのクローンや修正作業を行ってはならない。**

### サブエージェントに渡す情報

サブエージェントが自己完結して作業できるよう、以下の情報をすべてプロンプトに含める:

- リポジトリ名（owner/repo）
- デフォルトブランチ名
- アラートの詳細リスト（アラート番号、パッケージ名、現在バージョン、修正バージョン、エコシステム、severity、URL）をJSON形式で渡す
- 作業ディレクトリのパス（スキル実行時のカレントディレクトリ）
- 以下「サブエージェントの処理フロー」セクションの手順をそのまま含める

### サブエージェントの処理フロー（各リポジトリにつき 1 エージェント）

#### 1. ローカルリポジトリの準備

- 作業ディレクトリ配下にリポジトリ名のディレクトリが存在するか確認
- なければ `gh repo clone {owner}/{repo}`
- `git switch {default_branch}` でデフォルトブランチに切り替え
- `git pull` で最新化

#### 2. アラートのグルーピング

同一パッケージに複数のアラートがある場合、1つの PR にまとめる。

- アラートをパッケージ名でグルーピングする
- 各グループ内で最新の修正バージョン（最も高いバージョン）を採用する

#### 3. パッケージごとの修正（グループを順次処理）

**a. 既存 PR チェック:**
- ブランチ名: `fix/dependabot-{package_name}`
- 同名ブランチの open な PR が既に存在するか確認する:
  ```bash
  gh pr list --repo {owner}/{repo} --head {branch_name} --state open --json number,url
  ```
- PR が存在する場合、このパッケージを **スキップ** し、結果に「スキップ（既存PR あり: {pr_url}）」と記録して次へ進む

**b. ブランチ作成:**
- `git switch {default_branch}` でデフォルトブランチに戻る
- `git switch -c {branch_name}` で作業ブランチ作成

**c. 依存関係の更新（エコシステムに応じて）:**
- **npm**: `npm install {package}@{latest_fixed_version}`
- **pip**: `requirements.txt` / `pyproject.toml` 等のバージョンを編集し `pip install -r requirements.txt` 等
- **cargo**: `cargo update -p {package}`
- **gomod**: `go get {package}@{latest_fixed_version} && go mod tidy`
- **bundler**: `bundle update {gem}`
- **composer**: `composer require {package}:{latest_fixed_version}`
- **maven**: `pom.xml` のバージョンを直接編集
- **nuget**: `dotnet add package {package} --version {latest_fixed_version}`
- エコシステムが不明な場合: マニフェストファイルを特定して該当パッケージのバージョンを直接編集

**d. テスト検出・実行:**

依存関係の更新後、PR 作成前にテストを実行して互換性を検証する。

**i. テストフレームワークの検出（エコシステムに応じて）:**

以下の優先順位でテスト実行コマンドを検出する:

- **npm/yarn**: `package.json` の `scripts.test` が存在し、値が `echo "Error: no test specified" && exit 1` でなければ `npm test` を使用。`scripts` に `test:unit`, `test:integration` 等がある場合もそれぞれ実行する
- **pip (Python)**: `pytest.ini`, `pyproject.toml` の `[tool.pytest]`, `setup.cfg` の `[tool:pytest]` があれば `pytest`。`tox.ini` があれば `tox`。いずれもなければ `python -m pytest` を試行（テストディレクトリ `tests/`, `test/` の存在を確認）
- **cargo**: `cargo test`
- **gomod**: `go test ./...`
- **bundler**: `Rakefile` で `spec` タスクがあれば `bundle exec rake spec`、`.rspec` があれば `bundle exec rspec`、いずれもなければ `bundle exec rake test`
- **composer**: `composer test` または `vendor/bin/phpunit`
- **maven**: `mvn test`
- **nuget**: `dotnet test`

テストコマンドが検出できない場合は `test_status: no_test_env`（テスト環境未検出）と記録し、f（コミット前検証）に進む。

**ii. テストの実行:**

検出したコマンドでテストを実行する（タイムアウト: 5 分）。以下を記録する:
- 実行コマンド
- 終了コード（0: 成功, それ以外: 失敗）
- 失敗したテストケースの一覧（テスト出力から抽出）
- テスト出力の要約（最後の数十行）

テストが全て成功した場合は `test_status: passed` と記録し、iii（関連テストの有無チェック）を実施してから f（コミット前検証）に進む。
テストが失敗した場合は `test_status: failed` と記録し、e（テスト失敗時の修正試行）に進む。

**iii. 関連テストの有無チェック:**

テストが全パスした場合でも、更新パッケージに関連するテストが存在するかを確認する:

1. テストファイル群の中で、更新パッケージ名を `import`/`require`/`use` しているファイルを検索する
2. 更新パッケージを使用しているソースファイルを特定し、そのモジュール/関数に対するテストが存在するか確認する

関連テストが見つからない場合、`missing_related_tests: true` と記録する（PR 本文に記載する）。

**e. テスト失敗時の修正試行:**

テストが失敗した場合、ソースコードの修正を試みる。**最大 3 ラウンド** の修正サイクルを実施する。

**ガードレール（テストファイル変更禁止）:**

修正を行う前に、以下のファイルは **絶対に変更してはならない**:
- `test/`, `tests/`, `__tests__/`, `spec/`, `specs/` ディレクトリ配下の全ファイル
- ファイル名が以下のパターンにマッチするファイル: `test_*.py`, `*_test.py`, `*_test.go`, `*_test.rs`, `*.test.js`, `*.test.ts`, `*.test.jsx`, `*.test.tsx`, `*.spec.js`, `*.spec.ts`, `*.spec.jsx`, `*.spec.tsx`, `*_spec.rb`, `*Test.java`, `*Test.php`
- テスト設定ファイル: `conftest.py`, `jest.config.*`, `vitest.config.*`, `.rspec`, `pytest.ini`
- テストの期待値を変更するような修正（テストをパスさせるためだけにロジックの仕様を変える）は行わない
- 修正対象はあくまで「バージョンアップに伴う API 変更への追従」に限定する

**修正サイクル（最大 3 回）:**

1. 失敗したテストのエラーメッセージを分析する
2. 更新したパッケージの破壊的変更（breaking changes）を特定する（CHANGELOG やマイグレーションガイドがあれば参照、エラーメッセージから API 変更パターンを推測: 関数名変更、引数変更、インポートパス変更、型変更等）
3. **修正対象ファイルがテストファイルパターンに該当しないことを確認してから**ソースコードを修正する
4. テストを再実行する
5. 成功すれば `test_status: fixed` と記録し、修正内容の要約も記録して f に進む
6. 失敗が続く場合、次のラウンドへ

3 ラウンドで修正できなかった場合:
- `test_status: unfixed` と記録する
- 残っている失敗テストの詳細（テスト名、エラーメッセージ）を記録する
- 修正を試みた内容と結果を記録する
- 修正の変更はそのまま残す（部分的にでも改善していれば価値がある）
- f に進む（PR は作成するが、本文に未修正の失敗テスト情報を記載する）

**f. コミット前検証・コミット・プッシュ:**

コミット前に、テストファイルが誤って変更されていないかを確認する:

```bash
git diff --name-only
```

変更ファイルの中に以下のパターンに一致するものがあれば `git checkout -- {file}` で変更を取り消す:
- `test/`, `tests/`, `__tests__/`, `spec/`, `specs/` 配下のファイル
- `*test*.*`, `*spec*.*`, `*Test.*` 等のテストファイルパターン

確認後にコミット・プッシュする:
```bash
git add .
git commit -m "fix: update {package} to {latest_fixed_version} (dependabot alerts #{numbers})"
git push -u origin {branch_name}
```

**g. PR 作成:**

`test_status` と `missing_related_tests` の値に応じて PR 本文の `## Test Verification` セクションを構成する。

```bash
gh pr create \
  --title "fix: update {package} to {latest_fixed_version}" \
  --body "$(cat <<'EOF'
## Summary
- Fixes Dependabot alerts: #{number1}, #{number2}, ...
- Updates {package} from {current_version} to {latest_fixed_version}
- Severities: {severity1}, {severity2}, ...

## Dependabot Alerts
- {alert_url_1}
- {alert_url_2}
- ...

## Test Verification
{test_verification_section}
EOF
)" \
  --repo {owner}/{repo}
```

`{test_verification_section}` は `test_status` に応じて以下のいずれかを記載する:

**`test_status: passed` の場合:**
```
- :white_check_mark: All tests passed
- Test command: `{test_command}`
```

**`test_status: passed` かつ `missing_related_tests: true` の場合:**
```
- :white_check_mark: All existing tests passed
- Test command: `{test_command}`
- :information_source: No tests found that directly cover `{package}` usage. Consider adding tests for modules that depend on this package.
```

**`test_status: fixed` の場合:**
```
- :warning: Tests initially failed but were fixed
- Test command: `{test_command}`
- Fixes applied:
  - {description_of_fix_1}
  - {description_of_fix_2}
```

**`test_status: unfixed` の場合:**
```
- :x: Some tests are still failing after automated fix attempts
- Test command: `{test_command}`
- Failing tests:
  - `{test_name_1}`: {error_summary_1}
  - `{test_name_2}`: {error_summary_2}
- Fix attempts:
  - Round 1: {what_was_tried_1}
  - Round 2: {what_was_tried_2}
  - Round 3: {what_was_tried_3}
- **Manual review required**: The above test failures need human intervention.
```

**`test_status: no_test_env` の場合:**
```
- :information_source: No test environment detected in this repository
```

**h. エラー時:**
- ブランチを削除する: `git switch {default_branch} && git branch -D {branch_name}`
- スキップして次のパッケージへ進む
- 結果に「失敗」と理由を記録する

#### 4. 結果を返却

各パッケージの対応結果（成功/失敗、テスト結果、対象アラート番号、PR URL）をまとめて返す。

---

## Step 4: 結果回収・レポート

全サブエージェントの完了を `TaskOutput`（`block: true`）で待機し、各エージェントの結果を回収する。結果をまとめてテーブル形式で表示する:

| リポジトリ | パッケージ | アラート # | テスト結果 | 対応結果 | PR URL |
|-----------|-----------|-----------|-----------|---------|--------|
| owner/repo | lodash | #123, #789 | passed | 成功 | URL |
| owner/repo | express | #456 | fixed (2 fixes) | 成功 | URL |
| owner/repo | axios | #101 | unfixed (3 failures) | 成功(要確認) | URL |
| owner/repo | react | #202 | no tests | 成功 | URL |
| owner/repo | webpack | #303 | - | スキップ（既存PR） | 既存PR URL |
| owner/repo | chalk | #404 | - | 失敗（理由） | - |
