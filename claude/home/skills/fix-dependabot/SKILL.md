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

#### 3. パッケージごとの評価（Phase 1）

各パッケージグループを順次処理し、一時ブランチ上で更新・テスト・修正試行を行う。**この Phase では PR を作成しない。** 評価結果を記録して一時ブランチを破棄する。

**a. 既存 PR チェック:**
- 以下のブランチ名で open な PR が既に存在するか確認する:
  - `fix/dependabot-{package_name}`（個別 PR）
  - `fix/dependabot-security-updates`（まとめ PR）
  ```bash
  gh pr list --repo {owner}/{repo} --head fix/dependabot-{package_name} --state open --json number,url
  gh pr list --repo {owner}/{repo} --head fix/dependabot-security-updates --state open --json number,url
  ```
- いずれかの PR が存在する場合、このパッケージを **スキップ** し、結果に「スキップ（既存PR あり: {pr_url}）」と記録して次へ進む

**b. 一時ブランチ作成:**
- `git switch {default_branch}` でデフォルトブランチに戻る
- `git switch -c tmp/dependabot-assess-{package_name}` で一時評価ブランチ作成

**b2. 直接依存 / 間接依存の判定:**

エコシステムに応じてマニフェストファイルを確認し、アラート対象パッケージが直接依存か間接依存かを判定する:

- **npm**: `package.json` の `dependencies` / `devDependencies` にパッケージ名が含まれるか
- **pip**: `requirements.txt` / `pyproject.toml` の `[project.dependencies]` / `setup.py` の `install_requires` に含まれるか
- **cargo**: `Cargo.toml` の `[dependencies]` / `[dev-dependencies]` に含まれるか
- **gomod**: `go.mod` の `require` ディレクティブに直接記載されているか（`// indirect` コメントがないか）
- **bundler**: `Gemfile` に直接記載されているか
- **composer**: `composer.json` の `require` / `require-dev` に含まれるか
- **maven**: `pom.xml` の `<dependencies>` に直接記載されているか
- **nuget**: `*.csproj` の `<PackageReference>` に含まれるか

判定結果を `dependency_type: direct` または `dependency_type: indirect` として記録する。直接依存の場合は c1 に、間接依存の場合は c2 に進む。

**c1. 依存関係の更新 — 直接依存の場合（エコシステムに応じて）:**
- **npm**: `npm install {package}@{latest_fixed_version}`
- **pip**: `requirements.txt` / `pyproject.toml` 等のバージョンを編集し `pip install -r requirements.txt` 等
- **cargo**: `cargo update -p {package}`
- **gomod**: `go get {package}@{latest_fixed_version} && go mod tidy`
- **bundler**: `bundle update {gem}`
- **composer**: `composer require {package}:{latest_fixed_version}`
- **maven**: `pom.xml` のバージョンを直接編集
- **nuget**: `dotnet add package {package} --version {latest_fixed_version}`
- エコシステムが不明な場合: マニフェストファイルを特定して該当パッケージのバージョンを直接編集

`update_method: normal` と記録し、d（テスト検出・実行）に進む。

**c2. 依存関係の更新 — 間接依存の場合:**

まず、直接依存ライブラリのバージョン制約内でロックファイル更新により対応可能かを確認する。

**i. ロックファイル更新で対応可能か確認する:**
- **npm**: `npm update {package}` を実行後、`npm ls {package}` で解決バージョンが修正バージョン以上かチェック
- **pip**: `pip install --upgrade {direct_parent}` 後に `pip show {package}` でバージョン確認
- **cargo**: `cargo update -p {package}` 後に `cargo tree -p {package}` でバージョン確認
- **gomod**: `go get -u {direct_parent}` → `go mod tidy` 後に `go list -m {package}` でバージョン確認
- **bundler**: `bundle update {package}` 後に `bundle show {package}` でバージョン確認
- **composer**: `composer update {package}` 後に `composer show {package}` でバージョン確認
- **maven**: `mvn versions:use-latest-releases -Dincludes={package}` 後にバージョン確認
- **nuget**: `dotnet restore` 後にバージョン確認

**ii. 対応可能だった場合**（解決バージョンが修正バージョン以上）:
`update_method: lock_refresh` と記録し、d（テスト検出・実行）に進む。

**iii. 対応不可能だった場合**（直接依存のバージョン制約が修正バージョンを許容しない）:
アラートの severity を確認する:

- **severity が high または critical の場合:** override で強制的にバージョンを指定する:
  - **npm**: `package.json` の `overrides` フィールドに `"{package}": "{latest_fixed_version}"` を追加し `npm install`
  - **yarn**: `package.json` の `resolutions` フィールドに `"{package}": "{latest_fixed_version}"` を追加し `yarn install`
  - **cargo**: `Cargo.toml` の `[patch.crates-io]` セクションにパッチ指定
  - **gomod**: `go.mod` に `replace {package} => {package} {latest_fixed_version}` を追加し `go mod tidy`
  - **bundler**: `Gemfile` の末尾に `gem '{package}', '{latest_fixed_version}'` を追加し `bundle install`
  - **composer**: `composer.json` の `require` に直接追加し `composer update`
  - **maven**: `pom.xml` の `<dependencyManagement>` セクションにバージョンを追加
  - **nuget**: `Directory.Packages.props` がある場合はそこに、なければ `*.csproj` に直接 `<PackageReference>` を追加

  `update_method: override` と記録し、d（テスト検出・実行）に進む。

- **severity が medium または low の場合:** このパッケージを **スキップ** する。
  結果に「スキップ（間接依存・severity {level}・override 対象外）」と記録し、一時ブランチを破棄して次のパッケージに進む。

**d. テスト検出・実行:**

依存関係の更新後にテストを実行して互換性を検証する。

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

テストコマンドが検出できない場合は `test_status: no_test_env`（テスト環境未検出）と記録し、f（結果記録・ブランチ破棄）に進む。

**ii. テストの実行:**

検出したコマンドでテストを実行する（タイムアウト: 5 分）。以下を記録する:
- 実行コマンド
- 終了コード（0: 成功, それ以外: 失敗）
- 失敗したテストケースの一覧（テスト出力から抽出）
- テスト出力の要約（最後の数十行）

テストが全て成功した場合は `test_status: passed` と記録し、iii（関連テストの有無チェック）を実施してから f（結果記録・ブランチ破棄）に進む。
テストが失敗した場合は `test_status: failed` と記録し、e（テスト失敗時の修正試行）に進む。

**iii. 関連テストの有無チェック:**

テストが全パスした場合でも、更新パッケージに関連するテストが存在するかを確認する:

1. テストファイル群の中で、更新パッケージ名を `import`/`require`/`use` しているファイルを検索する
2. 更新パッケージを使用しているソースファイルを特定し、そのモジュール/関数に対するテストが存在するか確認する

関連テストが見つからない場合、`missing_related_tests: true` と記録する。

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
- f に進む

**f. 結果記録・一時ブランチ破棄:**

以下の情報を評価結果として記録する:
- パッケージ名、現在バージョン、修正バージョン
- エコシステム、更新コマンド
- `dependency_type`（`direct` / `indirect`）
- `update_method`（`normal` / `lock_refresh` / `override`）
- `test_status`（`passed` / `fixed` / `unfixed` / `no_test_env`）
- `missing_related_tests`（`true` / `false`）
- 修正試行の内容（`fixed` または `unfixed` の場合）
- 失敗テストの詳細（`unfixed` の場合）
- テストコマンド

一時ブランチを破棄してデフォルトブランチに戻る:
```bash
git switch {default_branch}
git branch -D tmp/dependabot-assess-{package_name}
```

**g. エラー時:**
- 一時ブランチを破棄する: `git switch {default_branch} && git branch -D tmp/dependabot-assess-{package_name}`
- スキップして次のパッケージへ進む
- 結果に「失敗」と理由を記録する

#### 4. PR 作成（Phase 2）

Phase 1 の評価結果に基づき、パッケージを **十分グループ** と **不十分グループ** に分類して PR を作成する。

**分類基準:**
- **十分グループ**（まとめ PR）: `test_status` が `passed`（`missing_related_tests` が `false`）、`fixed`、`no_test_env` のいずれか
- **不十分グループ**（個別 PR）: `test_status` が `unfixed`、または `passed` かつ `missing_related_tests: true`

##### 4a. まとめ PR（十分グループ）

十分グループが 0 件の場合はスキップする。

1. 既存の `fix/dependabot-security-updates` ブランチの open PR を確認する:
   ```bash
   gh pr list --repo {owner}/{repo} --head fix/dependabot-security-updates --state open --json number,url
   ```
   PR が存在する場合は、十分グループ全体をスキップする。

2. ブランチ作成:
   ```bash
   git switch {default_branch}
   git switch -c fix/dependabot-security-updates
   ```

3. 十分グループの全パッケージの依存関係を一括更新する（Phase 1 と同じ更新コマンドを順次実行）。`fixed` だったパッケージについては、Phase 1 で行ったソースコード修正も再適用する。

4. **最終統合テスト実行**: 全パッケージが同時に更新された状態でテストを実行する（タイムアウト: 5 分）。
   - テスト成功 → 5 に進む
   - テスト失敗 → 失敗原因のパッケージを特定し、そのパッケージを不十分グループに移動する。残りのパッケージで 2〜4 を再試行する。再試行は最大 1 回とし、それでも失敗する場合は十分グループ全体の PR 作成を中止し、全パッケージを個別 PR（4b）として処理する。

5. コミット前検証: テストファイルが誤って変更されていないか確認する:
   ```bash
   git diff --name-only
   ```
   テストファイルパターンに一致するファイルがあれば `git checkout -- {file}` で変更を取り消す。

6. コミット・プッシュ:
   ```bash
   git add .
   git commit -m "fix: update security dependencies ({package1}, {package2}, ...)"
   git push -u origin fix/dependabot-security-updates
   ```

7. まとめ PR 作成:
   ```bash
   gh pr create \
     --title "fix: update {n} security dependencies" \
     --body "$(cat <<'EOF'
   ## Summary
   - Fixes Dependabot alerts: #{number1}, #{number2}, ...
   - Updates {n} packages:
     - {package1}: {old_version} → {new_version} ({severity}) [direct]
     - {package2}: {old_version} → {new_version} ({severity}) [indirect: lock refresh]
     - {package3}: {old_version} → {new_version} ({severity}) [indirect: override]
     - ...

   ## Dependabot Alerts
   - {alert_url_1}
   - {alert_url_2}
   - ...

   ## Test Verification (per package)
   ### {package1}
   {test_verification_for_package1}

   ### {package2}
   {test_verification_for_package2}

   ### Final Integration Test
   - :white_check_mark: All tests passed with all packages updated simultaneously
   - Test command: `{test_command}`
   EOF
   )" \
     --repo {owner}/{repo}
   ```

   各パッケージの `{test_verification_for_packageN}` は `test_status` に応じて以下を記載する:

   **`test_status: passed` の場合:**
   ```
   - :white_check_mark: All tests passed
   ```

   **`test_status: fixed` の場合:**
   ```
   - :warning: Tests initially failed but were fixed
   - Fixes applied:
     - {description_of_fix_1}
   ```

   **`test_status: no_test_env` の場合:**
   ```
   - :information_source: No test environment detected
   ```

##### 4b. 個別 PR（不十分グループ）

不十分グループが 0 件の場合はスキップする。

パッケージごとに以下を実行する:

1. ブランチ作成:
   ```bash
   git switch {default_branch}
   git switch -c fix/dependabot-{package_name}
   ```

2. 依存関係を更新する（Phase 1 と同じ更新コマンドを実行）。`unfixed` の場合は Phase 1 で行った修正試行の変更も再適用する。

3. コミット前検証: テストファイルが誤って変更されていないか確認する:
   ```bash
   git diff --name-only
   ```
   テストファイルパターンに一致するファイルがあれば `git checkout -- {file}` で変更を取り消す。

4. コミット・プッシュ:
   ```bash
   git add .
   git commit -m "fix: update {package} to {latest_fixed_version} (dependabot alerts #{numbers})"
   git push -u origin fix/dependabot-{package_name}
   ```

5. 個別 PR 作成:
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

   **`test_status: passed` かつ `missing_related_tests: true` の場合:**
   ```
   - :white_check_mark: All existing tests passed
   - Test command: `{test_command}`
   - :information_source: No tests found that directly cover `{package}` usage. Consider adding tests for modules that depend on this package.
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

6. エラー時:
   - ブランチを削除する: `git switch {default_branch} && git branch -D fix/dependabot-{package_name}`
   - スキップして次のパッケージへ進む
   - 結果に「失敗」と理由を記録する

#### 5. 結果を返却

各パッケージの対応結果（成功/失敗、テスト結果、PR 種別、対象アラート番号、PR URL）をまとめて返す。

---

## Step 4: 結果回収・レポート

全サブエージェントの完了を `TaskOutput`（`block: true`）で待機し、各エージェントの結果を回収する。結果をまとめてテーブル形式で表示する:

| リポジトリ | パッケージ | アラート # | 依存種別 | 更新方法 | テスト結果 | PR 種別 | 対応結果 | PR URL |
|-----------|-----------|-----------|---------|---------|-----------|--------|---------|--------|
| owner/repo | lodash | #123, #789 | direct | normal | passed | まとめ | 成功 | URL |
| owner/repo | express | #456 | direct | normal | fixed (2 fixes) | まとめ | 成功 | URL（同上） |
| owner/repo | semver | #789 | indirect | lock_refresh | passed | まとめ | 成功 | URL（同上） |
| owner/repo | json5 | #800 | indirect | override | no_test_env | まとめ | 成功 | URL（同上） |
| owner/repo | axios | #101 | direct | normal | unfixed (3 failures) | 個別 | 成功(要確認) | URL |
| owner/repo | react | #202 | direct | normal | passed (関連テストなし) | 個別 | 成功 | URL |
| owner/repo | minimist | #505 | indirect | - | - | - | スキップ（severity low） | - |
| owner/repo | webpack | #303 | - | - | - | - | スキップ（既存PR） | 既存PR URL |
| owner/repo | chalk | #404 | - | - | - | - | 失敗（理由） | - |
