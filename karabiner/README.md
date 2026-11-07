# karabiner

Karabiner-Elements の設定。`~/.config/karabiner` にディレクトリごとリンクする
（Karabiner は保存時にファイルを置き換えるため、ファイル単位のリンクは壊れる）。

## 内容

- 全キーボード共通: Caps Lock → 左 Control。左右 Cmd の単押しで 英数 / かな（組み合わせ押しは通常の Cmd）。
- 全キーボード共通: 左右 Ctrl の単押しで 英数 ⇄ かな をトグル（組み合わせ押しは通常の Ctrl）。
  Karabiner の `input_source_if` で Apple 日本語 IME の現在モードを見て切り替えるため、Cmd 単押しや
  メニューバーで切り替えた後もずれない。Caps Lock は Ctrl に化けているので Caps 単押しでも同じ動きになる。
- Realforce（US 配列・Windows キー配置。Topre vendor 2131 / product 795）:
  Alt ⇄ Cmd、Win ⇄ Option を入れ替える。本体側（Realforce Connect 等）のキー入れ替えは
  既定に戻しておくこと（二重に入れ替わって元に戻ってしまう）。
  product 779 は同じキーボードの別接続モードと想定して同じ設定を入れてある。
- F1〜F12 は標準のファンクションキーとして扱う（Function keys タブの
  「Use all F1, F2, etc. keys as standard function keys」）。Realforce の Fn は本体内で処理されて
  Mac に届かないため、Fn+F12 で F12 を出す前提が成り立たない。この設定は karabiner.json ではなく
  macOS の `com.apple.keyboard.fnState` に保存されるので、`install.sh` で書き込む。
  音量などのメディア操作は REALFORCE CONNECT の Fn レイヤーに割り当てる。
- macOS の「キーボード → 修飾キー」は既定のままにする。Karabiner が掴んだキーボードの入力は
  仮想キーボード経由になり、macOS 側のキーボード別設定は効かないため。

## 注意

- `automatic_backups/` は Karabiner が保存のたびに書く世代バックアップ。追跡しない。
- root で動く Core Service が設定を読むため、このリポジトリが `~/Documents` 配下にある間は
  Karabiner-Core-Service にフルディスクアクセスが必要。
