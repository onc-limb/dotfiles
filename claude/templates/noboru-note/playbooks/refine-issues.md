# Playbook: 既存 Issue の粒度分割・Priority/Size 設定（全自動）

GitHub Project (`noboru-note-project` #1) の既存 Issue を機械的に棚卸しし、`issue-guidelines.md` の基準に沿って分割・Priority/Size 自動設定を行う手順書。

ユーザー指示により **全自動実行モード**。`needs-human-review` ラベル必須付与で人間レビューを担保する。

## 前提

- セットアップ完了（`SKILL.md`「セットアップ手順」）
- `gh auth status` で `Token: env var GH_TOKEN`
- CWD は noboru-note 親ディレクトリ
- `cache/` `logs/` 存在
- 1 サイクルあたりの分割上限: **5 件**（超える場合は優先度高い 5 件のみ処理し、残りは `logs/refine-deferred-*.md` に記録）

## ID 類

`PROJECT_ID` / 各 Field ID / Option ID は `PROJECT.md` 参照。本文ではシェル変数名（`PROJECT_ID`, `PRIORITY_FIELD`, `SIZE_FIELD`, `HIGH/MEDIUM/LOW`, `S/M/L` 等）として扱う。

---

## Step 1: 棚卸しクエリ（read-only）

### 1-1. Project 全 item の取得

```bash
gh project item-list 1 --owner noboru-note --format json --limit 200 \
  > cache/project-items.json
```

### 1-2. 全 open Issue の取得

```bash
for r in noboru-note noboru-note-mobile noboru-note-analyze .github-private; do
  gh issue list -R noboru-note/$r --state open --limit 200 \
    --json number,url,title,body,labels,createdAt,updatedAt
done | jq -s 'add' > cache/all-open-issues.json
```

### 1-3. Project 未追加 Issue の検出

```bash
jq --slurpfile p cache/project-items.json '
  map(select(.url as $u
    | ($p[0].items // [])
    | map(.content.url) | index($u) | not))
' cache/all-open-issues.json > cache/missing-from-project.json
```

### 1-4. Priority / Size 未設定の検出

```bash
jq '.items | map(select(.priority == null or .size == null))' \
  cache/project-items.json > cache/needs-priority-size.json
```

### 1-5. In progress 滞留検出（≥14 日）

```bash
CUTOFF=$(date -v-14d -u +%Y-%m-%dT%H:%M:%SZ)
jq --arg cutoff "$CUTOFF" '
  .items | map(select(.status == "In progress" and .updatedAt < $cutoff))
' cache/project-items.json > cache/stale-in-progress.json
```

---

## Step 2: 粒度判定 + 自動分割

`issue-guidelines.md`「大きすぎる兆候（分割を検討）」を機械化する。

### 2-1. 検出ロジック

| 兆候 | 検出方法 | 重み |
|---|---|---|
| 受け入れ条件 ≥ 5 | 本文中の `^- \[[ x]\]` 行数を grep | 2 点 |
| 抽象タイトル | タイトルが `(全体|リファクタリング|機能|改善)` を含む | 1 点 |
| 複数リポ横断 | 本文に他リポ参照（`noboru-note-mobile/` 等）を含む | 2 点 |
| 段階内包 | 本文に `(まず.*次に|設計.*実装|MVP.*拡張)` を含む | 1 点 |

合計 **2 点以上** で分割候補。

```bash
# 全 open Issue について判定
jq -r '.[] | "\(.number)|\(.title)|\(.body | gsub("\n"; "\\n"))|\(.url)"' \
  cache/all-open-issues.json | while IFS='|' read -r num title body url; do
  score=0
  ac_count=$(echo -e "$body" | grep -cE '^- \[[ x]\]')
  [ "$ac_count" -ge 5 ] && score=$((score + 2))
  echo "$title" | grep -qE '(全体|リファクタリング|機能全体|改善全般)' && score=$((score + 1))
  echo -e "$body" | grep -qE '(noboru-note-mobile/|noboru-note-analyze/|noboru-note/)' \
    && score=$((score + 2))
  echo -e "$body" | grep -qE '(まず.*次に|設計.*実装|MVP.*拡張)' && score=$((score + 1))
  if [ "$score" -ge 2 ]; then
    echo "$num|$score|$ac_count|$url|$title"
  fi
done > cache/split-candidates.txt
```

### 2-2. 自動分割の実行

候補ごとに以下を実行（上限 5 件）:

```bash
head -5 cache/split-candidates.txt | while IFS='|' read -r num score ac_count url title; do
  # 元 Issue を取得
  PARENT_NODE=$(gh issue view $num -R noboru-note/<repo> --json id --jq .id)
  PARENT_BODY=$(gh issue view $num -R noboru-note/<repo> --json body --jq .body)

  # 受け入れ条件を抽出
  echo "$PARENT_BODY" | grep -E '^- \[[ x]\]' > /tmp/ac-list.txt

  # 子 Issue を起票
  while IFS= read -r ac; do
    AC_TEXT=$(echo "$ac" | sed 's/^- \[[ x]\] //')
    CHILD_URL=$(gh issue create -R noboru-note/<repo> \
      --title "$AC_TEXT" \
      --body "親 Issue: $url

## 背景
$title から自動分割（refine-issues playbook）

## 受け入れ条件
- [ ] $AC_TEXT" \
      --label needs-human-review)

    CHILD_NODE=$(gh issue view "$(basename $CHILD_URL)" -R noboru-note/<repo> --json id --jq .id)

    # Sub-issues として親に紐付け
    gh api graphql -f query='
      mutation($parent:ID!, $child:ID!) {
        addSubIssue(input:{issueId:$parent, subIssueId:$child}) {
          subIssue { number }
        }
      }' -F parent="$PARENT_NODE" -F child="$CHILD_NODE"

    # Project に追加
    gh project item-add 1 --owner noboru-note --url "$CHILD_URL"
  done < /tmp/ac-list.txt

  # 親 Issue 本文を再構成（子 Issue 一覧をチェックボックス化）
  # ※ 詳細は実装時に gh issue edit --body-file で更新
done
```

> `addSubIssue` mutation は GitHub の Sub-issues 機能（2024 年 GA）に基づく。API 変更時は `gh api graphql --help` または GitHub GraphQL Explorer で最新 mutation 名を確認。

### 2-3. 統合候補の検出（参考）

issue-guidelines.md「小さすぎる兆候」も同じ枠組みで検出可能だが、自動統合は破壊的なため **検出のみ・人間判断**:

```bash
# 受け入れ条件 0 個 + 本文 100 文字未満
jq '[.[] | select((.body | length) < 100 and (.body | test("^- \\[[ x]\\]"; "m") | not))]' \
  cache/all-open-issues.json > cache/merge-candidates.json
```

`logs/refine-*.md` に「統合検討候補」として記録するのみ。

---

## Step 3: Priority 自動判定 + 設定

### 3-1. 判定ルール

`roadmap.md` の現在地（Phase 2 部分実装 / Phase 3 実装中）と Issue 内容を照合:

| Priority | 条件 |
|---|---|
| **High** | (a) 現フェーズ（Phase 2/3）の Critical Path、(b) Bug ラベル / Issue Type が Bug、(c) リリース直前タスク（App Store 関連、ストア審査等）、(d) 他 Issue の blocker |
| **Medium** | 現フェーズの通常機能 / UX 改善 / 軽微な Tech Debt |
| **Low** | 次フェーズ以降の準備 / Idea / Nice-to-have |

判定優先順: ①リリース直前キーワード（App Store/審査/blocker/critical）→ High、②Issue Type=Bug → High、③現フェーズ機能 → Medium、④次フェーズ以降/Idea → Low、⑤該当なし → Medium。

### 3-2. 設定実行

```bash
# PROJECT_ID, PRIORITY_FIELD, HIGH/MEDIUM/LOW は PROJECT.md から取得
# Priority 未設定 Issue を順に処理
jq -r '.[] | "\(.id)|\(.content.url)|\(.content.title)"' \
  cache/needs-priority-size.json | while IFS='|' read -r item_id url title; do
  # 判定ロジック適用（実装時は本文・ラベル取得して判定）
  PRIORITY_OPT="$MEDIUM"  # 例

  gh project item-edit \
    --project-id "$PROJECT_ID" \
    --id "$item_id" \
    --field-id "$PRIORITY_FIELD" \
    --single-select-option-id "$PRIORITY_OPT"
done
```

---

## Step 4: Size 自動判定 + 設定

### 4-1. 判定ルール

| Size | 条件 |
|---|---|
| **S** | 受け入れ条件 1〜2 個 / 単一ファイル変更 / 設定値変更レベル |
| **M** | 受け入れ条件 3〜4 個 / 複数ファイル / 単一レイヤー（API のみ・UI のみ等） |
| **L** | 受け入れ条件 5+ 個 → **Step 2 で分割対象**。残った場合のみ L |

### 4-2. 設定実行

```bash
# SIZE_FIELD, S/M/L は PROJECT.md から取得
jq -r '.[] | "\(.id)|\(.content.url)|\(.content.body)"' \
  cache/needs-priority-size.json | while IFS='|' read -r item_id url body; do
  ac_count=$(echo "$body" | grep -cE '^- \[[ x]\]')
  if [ "$ac_count" -le 2 ]; then SIZE_OPT="$S"
  elif [ "$ac_count" -le 4 ]; then SIZE_OPT="$M"
  else SIZE_OPT="$L"
  fi

  gh project item-edit \
    --project-id "$PROJECT_ID" \
    --id "$item_id" \
    --field-id "$SIZE_FIELD" \
    --single-select-option-id "$SIZE_OPT"
done
```

---

## Step 5: Project 未追加 Issue を一括追加

`cache/missing-from-project.json` の各 Issue を Project に追加:

```bash
jq -r '.[].url' cache/missing-from-project.json | while read -r url; do
  gh project item-add 1 --owner noboru-note --url "$url"
done
```

追加後、Step 3〜4 の Priority/Size 判定を再実行する。

---

## Step 6: 滞留 In progress の通知

自動状態遷移は行わない（人間判断）。`logs/refine-*.md` に列挙:

```bash
jq -r '.[] | "- [\(.content.title)](\(.content.url)) — 最終更新: \(.updatedAt)"' \
  cache/stale-in-progress.json
```

---

## Step 7: ログ記録

```bash
TS=$(date +%Y%m%d-%H%M)
cat > logs/refine-${TS}.md <<EOF
# Refine 実行ログ（${TS}）

## 棚卸し結果
- Project 全 item 数: $(jq '.items | length' cache/project-items.json)
- Project 未追加 Issue: $(jq 'length' cache/missing-from-project.json) 件
- Priority/Size 未設定: $(jq 'length' cache/needs-priority-size.json) 件
- 滞留 In progress (≥14日): $(jq 'length' cache/stale-in-progress.json) 件
- 分割候補: $(wc -l < cache/split-candidates.txt) 件
- 統合検討候補: $(jq 'length' cache/merge-candidates.json) 件

## 実施内容
- 分割実行: N 件（上限 5）
  - 親 #X → 子 #Y, #Z, ...
- Priority 設定: N 件
- Size 設定: N 件
- Project 追加: N 件

## 人間判断が必要な項目
### 滞留 In progress
- ...

### 統合検討候補
- ...

### 分割繰越（上限超過分）
- ...
EOF
```

`logs/run-${TS}.md` にも 1 行サマリで追記する。

---

## 想定リスクと緩和策

| リスク | 緩和策 |
|---|---|
| 自動分割で誤った受け入れ条件分け | `needs-human-review` 必須付与 + 親 Issue に「自動分割: 必要なら統合してください」と明記 |
| Priority 誤判定 | `project-board.md` 方針通り「AI が自動設定可、間違いは人間が直す」 |
| `addSubIssue` mutation 名変更 | サイクル開始時に `gh api graphql --help` で最新確認 |
| 大量更新でレート制限 | 1 サイクル: 分割 ≤5 件、Priority/Size 更新 ≤50 件 |
| `gh project item-list` の Status フィールド名差異 | `--format json` 出力を初回 `jq keys` で確認、cache/ に残す |

