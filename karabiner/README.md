# karabiner

Karabiner-Elements の設定。`~/.config/karabiner` にディレクトリごとリンクする
（Karabiner は保存時にファイルを置き換えるため、ファイル単位のリンクは壊れる）。

## 内容

- 全キーボード共通: Caps Lock → 左 Control。左右 Cmd の単押しで 英数 / かな（組み合わせ押しは通常の Cmd）。
- Realforce（US 配列・Windows キー配置。Topre vendor 2131 / product 795）:
  Alt ⇄ Cmd、Win ⇄ Option を入れ替える。本体側（Realforce Connect 等）のキー入れ替えは
  既定に戻しておくこと（二重に入れ替わって元に戻ってしまう）。
  product 779 は同じキーボードの別接続モードと想定して同じ設定を入れてある。
- macOS の「キーボード → 修飾キー」は既定のままにする。Karabiner が掴んだキーボードの入力は
  仮想キーボード経由になり、macOS 側のキーボード別設定は効かないため。

## 注意

- `automatic_backups/` は Karabiner が保存のたびに書く世代バックアップ。追跡しない。
- root で動く Core Service が設定を読むため、このリポジトリが `~/Documents` 配下にある間は
  Karabiner-Core-Service にフルディスクアクセスが必要。
