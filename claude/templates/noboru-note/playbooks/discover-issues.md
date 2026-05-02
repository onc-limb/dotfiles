# Playbook: 方針ドキュメントから新規 Issue を起票する

`.github-private/docs/` のプロダクト方針・ロードマップ・機能仕様を読み込み、未起票の機能・改善点を発見して新規 Issue として登録する手順書。

## 前提

- セットアップは `SKILL.md`「セットアップ手順」セクション完了済み
- `repo/.github-private/` が `pm-readonly` worktree として存在
- `gh auth status` で `Token: env var GH_TOKEN` を確認済み
- CWD は noboru-note 親ディレクトリ（`cache/` `logs/` `repo/` がある場所）

## モード

| モード | 起動条件 | 挙動 |
|---|---|---|
| **承認モード** | デフォルト | 候補リストを `logs/discover-YYYYMMDD-HHMM.md` に出力し、ユーザー承認後のみ起票 |
| **自動モード** | ユーザーが `--auto` / 「自動で」「全部起票して」等を明示 | 候補すべてを即起票（`needs-human-review` ラベル必須付与） |

自動モードでも 1 サイクルあたりの起票上限は **5 件** とする（レート制限・誤起票被害の限定）。超える候補数の場合は承認モードへフォールバックする。

---

## 手順

### Step 1: 現在地の特定

```bash
grep -n '現在地' repo/.github-private/docs/roadmap.md
```

「フェーズ別機能マッピング」表（roadmap.md の最終セクション）から現フェーズで実装すべき機能を列挙する。

```bash
sed -n '/フェーズ別機能マッピング/,$p' repo/.github-private/docs/roadmap.md
```

### Step 2: 方針ドキュメントの読み込み

候補抽出の判断材料として `repo/.github-private/docs/` の `roadmap.md` / `features.md` / `product-vision.md` / `repositories.md` / `issue-guidelines.md` を読む。worktree は毎サイクル `reset --hard` 同期されるので直接読めばよい。

### Step 3: 既存 Issue の棚卸し

```bash
mkdir -p cache
for r in noboru-note noboru-note-mobile noboru-note-analyze .github-private; do
  gh issue list -R noboru-note/$r --state all --limit 200 \
    --json number,title,body,labels,state,url \
    > cache/issues-$r.json
done
```

### Step 4: 候補抽出

「現フェーズで実装すべき機能」のうち、既存 Issue にマッチしないものを未起票候補とする。

重複判定はキーワード検索（issue-guidelines.md「重複検出のヒント」）に従う:

```bash
# 例: features.md § 2.1「セルフコンペ」が既存 Issue にあるか
jq -r '.[] | select(.title + .body | test("セルフコンペ|コンペ"; "i")) | .number' \
  cache/issues-noboru-note.json
```

候補ごとに以下のメタデータを保持: タイトル案 / Issue Type (Task/Bug/Feature/Idea/Docs) / 対象リポ / 本文 / Phase / 受け入れ条件数。

### Step 5: リポ振り分け判定

`issue-guidelines.md`「リポジトリ振り分け基準」に従う。複数リポ横断の場合は `.github-private` に親 Issue を立て、各リポに子 Issue を作って Sub-issues で紐付ける。

### Step 6: Issue 本文生成

issue-guidelines.md「Issue 本文に書く内容」表の Issue Type 別推奨項目を埋める。

**Feature の例**:
```markdown
## 背景（Why）
〜（roadmap / product-vision の該当箇所を引用）

## 目的・受け入れ条件
- [ ] 〜
- [ ] 〜

## 関連する機能仕様
`features.md § X.X`（リンク: https://github.com/noboru-note/.github-private/blob/main/docs/features.md#...）

## 関連 Issue / PR
- #N（あれば）
```

本文を一時ファイルに書き出す:
```bash
cat > /tmp/issue-body.md <<'EOF'
（上記内容）
EOF
```

### Step 7: 承認モードの場合 — 候補リスト出力

```bash
TS=$(date +%Y%m%d-%H%M)
cat > logs/discover-${TS}.md <<EOF
# 起票候補（${TS}）

| # | タイトル案 | リポ | Type | Phase |
|---|---|---|---|---|
| 1 | ... | noboru-note-mobile | Feature | 3 |
| 2 | ... | noboru-note | Task | 2 |
EOF
```

ユーザーへ提示して承認を得る（AskUserQuestion でどの候補を起票するか multiSelect で選んでもらう）。

**自動モードの場合**: Step 7 をスキップして Step 8 へ。ただし候補数 > 5 のときは承認モードへフォールバック。

### Step 8: 起票実行

```bash
URL=$(gh issue create -R noboru-note/<repo> \
  --title "<タイトル>" \
  --body-file /tmp/issue-body.md \
  --label needs-human-review)
echo "$URL"
```

> `needs-human-review` は **AI が起票・編集した Issue に必ず付与**（labels.md / agent-guardrails.md）。自動モードでも承認モードでも同じ。

### Step 9: Issue Type の設定（GraphQL）

gh CLI の `gh issue create --type` は未対応。GraphQL で設定する:

```bash
# Issue node ID を取得
ISSUE_NODE=$(gh api graphql -f query='
  query($owner:String!, $repo:String!, $num:Int!) {
    repository(owner:$owner, name:$repo) {
      issue(number:$num) { id }
    }
  }' -F owner=noboru-note -F repo=<repo> -F num=<number> --jq '.data.repository.issue.id')

# Org の Issue Type 一覧から目的の Type ID を取得
gh api graphql -f query='
  query { organization(login:"noboru-note") {
    issueTypes(first:20) { nodes { id name } }
  }}'

# Issue Type を設定
gh api graphql -f query='
  mutation($issueId:ID!, $typeId:ID!) {
    updateIssueIssueType(input:{issueId:$issueId, issueTypeId:$typeId}) {
      issue { number }
    }
  }' -F issueId="$ISSUE_NODE" -F typeId="<TypeID>"
```

Type ID は org レベルで固定なので、初回取得後 `cache/issue-types.json` に保存して再利用する。

### Step 10: Project へ追加

```bash
gh project item-add 1 --owner noboru-note --url "$URL"
```

### Step 11: Priority/Size 設定

判定ロジックは `playbooks/refine-issues.md` Step 3〜4 と同じ。Phase / 受け入れ条件数から自動判定して `gh project item-edit` で設定する。

PROJECT.md の Field/Option ID をそのまま使う:

```bash
PROJECT_ID=PVT_kwDOEIMLsc4BVBum
PRIORITY_FIELD=PVTSSF_lADOEIMLsc4BVBumzhQgYqs
SIZE_FIELD=PVTSSF_lADOEIMLsc4BVBumzhQgYqw

# 起票直後の item ID を取得
ITEM_ID=$(gh project item-list 1 --owner noboru-note --format json --limit 200 \
  | jq -r --arg url "$URL" '.items[] | select(.content.url == $url) | .id')

gh project item-edit \
  --project-id "$PROJECT_ID" --id "$ITEM_ID" \
  --field-id "$PRIORITY_FIELD" \
  --single-select-option-id "<High|Medium|Low の option ID>"
```

### Step 12: ログ記録

`logs/run-YYYYMMDD-HHMM.md` に追記:

```markdown
## 起票（discover-issues）

- モード: 承認 / 自動
- 起票件数: N 件
- 候補ファイル: logs/discover-YYYYMMDD-HHMM.md
- 起票結果:
  - https://github.com/noboru-note/<repo>/issues/<n> — Priority: High / Size: M / Phase: 3
  - ...
```

