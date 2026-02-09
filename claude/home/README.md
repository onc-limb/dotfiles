# claude/home

`~/.claude/` に個別シンボリックリンクされるユーザーレベルの設定ファイル。

## ファイル一覧

| ファイル | リンク先 | 説明 |
|---------|---------|------|
| `settings.json` | `~/.claude/settings.json` | 権限・言語などの設定 |
| `CLAUDE.md` | `~/.claude/CLAUDE.md` | グローバル指示 |
| `skills/` | `~/.claude/skills/` | ホームレベルのスキル |

## ホームレベルスキル

`claude/home/skills/` 配下のスキルは `~/.claude/skills/` にシンボリックリンクされ、どのプロジェクトからでも利用可能。

### install-template

テンプレート設定をプロジェクトディレクトリにコピーする。

```
/install-template                              # 利用可能なテンプレート一覧
/install-template obsidian                     # 現在のディレクトリにインストール
/install-template obsidian ~/Documents/vault   # 指定パスにインストール
```

テンプレートの追加: `claude/templates/<template-name>/` に `.claude/` と `CLAUDE.md` を配置すれば自動認識される。

## settings.json の設定方針

### language

応答言語を `"japanese"` に設定。

### permissions

3段階で制御される（評価順: deny → ask → allow）:

#### allow（自動許可）

| ルール | 対象 |
|-------|------|
| `Bash(git *)` | git操作全般（push, force push等はask/denyで上書き） |
| `WebFetch` | URL からのコンテンツ取得 |
| `WebSearch` | Web検索 |

パッケージマネージャやビルドツール（`npm run`, `pnpm run`, `make`等）はプロジェクトごとに異なるため、プロジェクトの `.claude/settings.json` で設定する。

#### ask（都度確認）

| ルール | 理由 |
|-------|------|
| `Bash(git push *)` | push先の確認 |
| `Bash(git checkout .)` | 未コミット変更の一括破棄 |
| `Bash(git restore .)` | 同上 |

上記以外でallow/denyに該当しない操作もaskになる（`rm`, `curl`, `docker`等）。

#### deny（完全ブロック）

**機密ファイル読み取り:**

| ルール | 対象 |
|-------|------|
| `Read(**/.env)`, `Read(**/.env.*)` | 環境変数・シークレット |
| `Read(**/secrets/**)` | シークレットディレクトリ |
| `Read(**/credentials*)` | 認証情報ファイル |
| `Read(**/.ssh/**)` | SSH鍵 |
| `Read(**/.gnupg/**)` | GPG鍵 |
| `Read(**/.aws/credentials)` | AWSアクセスキー |
| `Read(**/.npmrc)`, `Read(**/.pypirc)`, `Read(**/.netrc)` | パッケージマネージャ認証トークン |
| `Read(**/*.pem)`, `Read(**/*.key)` | 秘密鍵・証明書 |
| `Read(**/*.p12)`, `Read(**/*.pfx)`, `Read(**/*.keystore)` | 証明書ストア |

**破壊的操作:**

| ルール | 理由 |
|-------|------|
| `Bash(git push --force *)`, `Bash(git push -f *)` | リモート履歴の破壊 |
| `Bash(git reset --hard *)` | ローカル変更の不可逆な破棄 |
| `Bash(git clean *)` | 未追跡ファイルの完全削除 |
| `Bash(rm -rf *)` | 再帰的強制削除 |

`**` パターンはどの階層のファイルにもマッチする（プロジェクト外も含む）。

### スコープの優先順位

設定は下位スコープほど優先される:

```
User (~/.claude/settings.json)        ← このファイル（最低優先）
  ↓ オーバーライド
Project (.claude/settings.json)
  ↓ オーバーライド
Local (.claude/settings.local.json)   （最高優先）
```

プロジェクトレベルでdenyされた操作は、ここでallowしていてもブロックされる。

## Skill を SubAgent に切り替える判断基準

以下の兆候が見られたら、そのskillの処理をsubagentに委譲することを検討する:

1. **コンテキスト不足**: 実行中に「前の情報を覚えていない」「先ほどの内容を再度教えてください」といった応答が出始めたら、コンテキストウィンドウが溢れている
2. **大量ファイル読み取り**: 10ファイル以上を一度に読む必要がある処理（例: 月次報告書で30日分のノートを読む）
3. **処理時間の長さ**: 一つのskill実行が長時間に及び、途中で途切れる
4. **独立した前処理**: メインの対話に不要な中間データを大量に生成する処理（例: 全ノートスキャン→分類→結果のみ必要）

SubAgentにすべき処理の特徴:
- 読み取り中心（Read, Glob, Grep）で対話が不要
- 結果を要約して返せば十分（中間データは不要）
- メインの対話コンテキストを汚したくない

SubAgentにすべきでない処理の特徴:
- ユーザーとの対話が必要（refine-dailyのような補完作業）
- 少数ファイルの処理で済む
- メインコンテキストの情報が必要
