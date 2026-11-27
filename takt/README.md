# TAKT の設定

TAKT は仕事用とプライベート用で、グローバル設定の置き場（`TAKT_CONFIG_DIR`）を分けて動かす。
ワークフローと facets（判断の手順）は共通で、モデルと支払い方だけが違う。

**守ること: 仕事用は、どの経路でも Claude API・OpenCode・OpenRouter を使わない。** 迷ったら仕事用で動かす。

## 置き場

| 置き場 | 使われるとき | 支払い |
|---|---|---|
| `~/.takt-work` | wrapper（`bin/takt`）が仕事用と判定したとき | Claude のサブスクリプション + Codex のサブスクリプション |
| `~/.takt-private` | wrapper がプライベート用と判定したとき | Claude API（`billing=api`）。クレジットが切れたら Claude のサブスクリプション + OpenCode Go（`billing=subscription`）、OpenCode Go も上限なら Claude + Codex のサブスクリプション（`billing=codex`） |
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
billing=api             # api（Claude API。既定）| subscription（クレジット切れ用の組）| codex（OpenCode Go も上限のときの組）
anthropic_profile=takt  # billing=api で使う `ant auth login --profile <name>` のプロファイル
```

クレジットが切れて止まった run は、サブスクリプションの組で再開する:

```bash
TAKT_BILLING=subscription takt list   # retry →「Resume failed position」
```

OpenCode Go の使用上限（5 時間・週）で実装が止まったら、実装だけ Codex のサブスクリプションに替えて再開する:

```bash
TAKT_BILLING=codex takt list
```

## モデルの割当

- `common/targets.yaml`: どのステップ・persona にどの役割を当てるか（共通の表）。
- `work/profiles.yaml`・`private/profiles.yaml`: 役割に当てるモデル。プライベートの `assignments.credit-out` は、
  仕事用で Codex が受け持つ役割（`implementer`・`implementer-retry`）だけを OpenCode Go に替える。
  `assignments.go-out` は、同じ役割を仕事用と同じ Codex のモデルに替える。実装の順は Claude API → OpenCode Go → Codex。
- `build-runtime.py` が 2 つを合わせて `runtime.yaml` を作る。仕事用は `--deny opencode --deny openrouter` 付きで作る。

## ワークフロー（共通）

`agora-default`・`agora-design-flow` は、組み込みの `development-core`・`peer-review` を写して手を加えた
`agora-development-core`・`agora-peer-review` を呼ぶ（TAKT を上げたら組み込みとの差分を見る）。

- **計画の見直し**: 計画の後に `plan-review`（判断役のモデル）が 5 項目を確かめる。
  - 確かめる 5 項目:
    1. ゴールが受け入れ条件で閉じている
    2. 範囲外の扱いが決まっている
    3. 受け入れを run の中で確かめられる
    4. 設計判断を勝手に決めていない
    5. 1 回の run に収まる大きさ
  - 見直しの結果ごとの行き先:
    - 進める → テストの作成へ。
    - 計画を直す → `plan-revise`（最上位の計画モデル）→ `plan-review-2` へ。
    - 人に戻す → 中止。
  - 差し戻しは 1 回まで。`plan-review-2` からは計画へ戻る道がない。
- **計画の昇格**: テストの作成から計画へ戻ったときは、2 回目の `plan` が Opus から Fable に上がる（`promotion: [{at: 2}]`）。
- **修正の周回の上限**: レビュー → 裁定 → 修正の周回は、修正 3 回で止めて人に戻す。止めたときは、判定役が残っている問題と止めた理由を書く。
- **裁定の省略**: 最初のレビューで全員が承認したら、裁定を飛ばして最後の確認（`final-gate-direct`）へ進む。
  - 最後の確認には「裁定が無い」ことを伝える指示（`agora-final-gate-direct`）を足す。裁定が見るはずだった、レビューの「指摘にしなかった懸念」と計画の「留意点」も、ここで確かめる。
  - ここで REJECT になったら、修正へ直接は進まず、裁定へ回す（修正の工程は裁定のレポートを読むため）。
  - 修正の後のレビュー（2 周目以降）は、全員が承認しても裁定を通す（前の指摘が解消したことを記録するのが裁定のため）。
- **範囲の関門**:
  - 裁定とレビュー（`agora-review-scope`）: 前からある問題や範囲外の改善は、今回は直さず後続の課題として記録する。
  - 修正の確認（`agora-fix-verification-scope`）: 裁定が決めた受け入れ条件だけで判定する。

## テスト

```bash
bash takt/tests/test_wrapper.sh && TEST_BASH=/bin/bash bash takt/tests/test_wrapper.sh
python3 -m unittest discover -s takt/tests -p 'test_*.py'
```

`test_build_runtime.py` は、TAKT が入っていれば TAKT 自身の検証（`tests/validate-runtime.mjs`）でも生成物を確かめる。
`test_workflows.py` は、共通のワークフローを TAKT のローダーで読み、見直しの行き先・昇格・周回の上限の形を確かめる。
