# claude/home

`~/.claude/` に個別シンボリックリンクされるユーザーレベルの設定ファイル。

## ファイル一覧

| ファイル | リンク先 | 説明 |
|---------|---------|------|
| `settings.json` | `~/.claude/settings.json` | 権限・言語などの設定 |
| `CLAUDE.md` | `~/.claude/CLAUDE.md` | グローバル指示 |

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
