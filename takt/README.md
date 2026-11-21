# TAKT の設定

TAKT は仕事用とプライベート用で、グローバル設定の置き場（`TAKT_CONFIG_DIR`）を分けて動かす。
ワークフローと facets（判断の手順）は共通で、モデルと支払い方だけが違う。

**守ること: 仕事用は、どの経路でも Claude API・OpenCode・OpenRouter を使わない。** 迷ったら仕事用で動かす。

## 置き場

| 置き場 | 使われるとき | 支払い |
|---|---|---|
| `~/.takt-work` | wrapper（`bin/takt`）が仕事用と判定したとき | Claude のサブスクリプション + Codex のサブスクリプション |
| `~/.takt-private` | wrapper がプライベート用と判定したとき | Claude API（`billing=api`）。クレジットが切れたら Claude のサブスクリプション + OpenCode Go（`billing=subscription`） |
| `~/.takt` | wrapper を通らない起動（実行ファイルを直接呼んだとき） | 仕事用の設定の**コピー**（ここへの書き込みは dotfiles に戻らない） |

`install.sh` が 3 つの置き場に、`config.yaml`・`runtime.yaml`（生成）・`facets/`（リンク）・`workflows/`（コピー）を作る。
TAKT が入れる SDK（`claude-sdk`・`codex`・`opencode`）は置き場ごとに入れる:

```bash
TAKT_CONFIG_DIR=~/.takt-work    /opt/homebrew/bin/takt install claude-sdk   # codex も同じ
TAKT_CONFIG_DIR=~/.takt-private /opt/homebrew/bin/takt install opencode     # opencode はプライベートだけ
```

仕事用の置き場に `opencode` を入れると install.sh が失敗する。

## どちらで動くか（wrapper の判定）

プライベート用になるのは、次の 2 つがそろったときだけ。それ以外はすべて仕事用。

1. プロジェクト（git の top level。シンボリックリンクは解決する）が `~/Documents/onclimb-industries/` 配下にある。
2. プロジェクトに `.takt/private.conf` がある（linked worktree では、本体の checkout の `.takt/private.conf` も見る）。

`~/work/` 配下はいつも仕事用。仕事用で次が見つかったら、黙って進まずに止まる:

- `.takt/private.conf` や旧 `.takt/auth.conf`
- `TAKT_CONFIG_DIR` が `~/.takt-private` のまま（プライベート用の run の中からの起動）
- プロジェクトの `.takt/config.yaml`・`runtime.yaml` や `~/.takt-work` に `opencode`・`openrouter`・`api_key`・`base_url`・`assignments`
- 引数の `--provider` / `--model` に opencode・openrouter、`--runtime-assignment`、`--runtime-file`

仕事用では、課金を切り替える環境変数（`ANTHROPIC_*`・`CLAUDE_CODE_USE_*`・`OPENAI_API_KEY`・`CODEX_API_KEY`・
`OPENROUTER_*`・`TAKT_*_API_KEY` など）を消し、Anthropic のプロファイルの置き場を空のディレクトリに、
OpenCode の CLI を `/usr/bin/false` に向けてから起動する。

### `.takt/private.conf`

git の対象外に置く（仕事用のリポジトリには置かない）。

```
billing=api             # api（Claude API。既定）| subscription（クレジット切れ用の組）
anthropic_profile=takt  # billing=api で使う `ant auth login --profile <name>` のプロファイル
```

クレジットが切れて止まった run は、サブスクリプションの組で再開する:

```bash
TAKT_BILLING=subscription takt list   # retry →「Resume failed position」
```

## モデルの割当

- `common/targets.yaml`: どのステップ・persona にどの役割を当てるか（共通の表）。
- `work/profiles.yaml`・`private/profiles.yaml`: 役割に当てるモデル。プライベートの `assignments.credit-out` は、
  仕事用で Codex が受け持つ役割（`implementer`・`implementer-retry`）だけを OpenCode Go に替える。
- `build-runtime.py` が 2 つを合わせて `runtime.yaml` を作る。仕事用は `--deny opencode --deny openrouter` 付きで作る。

## テスト

```bash
bash takt/tests/test_wrapper.sh && TEST_BASH=/bin/bash bash takt/tests/test_wrapper.sh
python3 -m unittest discover -s takt/tests -p 'test_*.py'
```

`test_build_runtime.py` は、TAKT が入っていれば TAKT 自身の検証（`tests/validate-runtime.mjs`）でも生成物を確かめる。
