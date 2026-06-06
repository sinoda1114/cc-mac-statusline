# cc-mac-statusline

macOS 環境の [Claude Code](https://docs.anthropic.com/en/docs/claude-code) で動作する 2 行ステータスラインの設定一式。モデル名・effort レベル・コンテキスト使用率・cwd に加え、5 時間 / 7 日 / extra のレート制限バーを表示する。

```
Opus 4.8:max │ ✍️ 7% │ project

●●●●○○○○○○  46% ⏰ 17:10
●○○○○○○○○○  12% ⏰ 05/10(日) 01:00
```

> Windows 版は [cc-win-statusline](https://github.com/sinoda1114/cc-win-statusline) を参照。

## なぜ macOS 専用なのか

このスクリプトは `date -d` / `stat -c` という **GNU coreutils 構文** に依存している。macOS 標準の BSD 版 `date` / `stat` はこれらのオプションを解釈できず、レート制限のリセット時刻計算が壊れる。本リポジトリは Homebrew の coreutils（`gdate` / `gstat`）を PATH 先頭に差し込むことでこの問題を回避している。

## 動作環境

- macOS（Apple Silicon を想定。Homebrew が `/opt/homebrew` 配下）
- Claude Code v2.1.x
- [Homebrew](https://brew.sh/) 経由の以下:

```bash
brew install coreutils jq git
```

`coreutils` は `gdate` / `gstat` を提供する。スクリプトは `/opt/homebrew/opt/coreutils/libexec/gnubin` を PATH 先頭に追加して、`date` / `stat` を GNU 版として呼び出す。

> Intel Mac の場合は Homebrew prefix が `/usr/local` になるため、`statusline.sh` 冒頭の `export PATH=...` を `/usr/local/opt/coreutils/libexec/gnubin` に書き換える。

## インストール

### 自動（推奨）

```bash
git clone https://github.com/sinoda1114/cc-mac-statusline.git
cd cc-mac-statusline
bash install.sh
```

実行内容:
1. `~/.claude/statusline.sh` をコピーして実行権限を付与
2. `~/.claude/settings.json` の `statusLine` セクションを `jq` でマージ（既存ファイルはタイムスタンプ付きでバックアップ）
3. 依存コマンド（`bash` / `jq` / `git` / GNU `coreutils`）を検査

完了後、Claude Code を再起動すれば反映される。

### 手動

1. `template/statusline.sh` を `~/.claude/statusline.sh` にコピーし、`chmod +x` する
2. `~/.claude/settings.json` に以下をマージ:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline.sh",
    "refreshInterval": 5000
  }
}
```

## 表示の読み方

### 1 行目

| 要素 | 例 | 説明 |
|---|---|---|
| モデル:effort | `Opus 4.8:max` | effort は色温度（max=赤 … low=シアン）で危険度を表現 |
| ✍️ % | `✍️ 7%` | コンテキストウィンドウ使用率（90%↑赤 / 70%↑黄 / 50%↑橙 / それ以下緑） |
| ディレクトリ | `project` | cwd の basename |

### 2 行目以降（レート制限）

- 1 本目 … 5 時間枠の使用率バーとリセット時刻（HH:MM）
- 2 本目 … 7 日枠の使用率バーとリセット日時（MM/DD(曜日) HH:MM、曜日は日本語）
- `extra` … extra usage が有効な場合のみ。使用額 / 上限額

レート制限の値は Claude Code が stdin で渡す `rate_limits` から取得する。無い場合は `/tmp/claude/statusline-usage-cache.json` にフォールバックする。

## ネットワーク通信について

このスクリプトは**外部へのネットワーク通信を一切行わない**。表示する値はすべて Claude Code から渡される stdin の JSON と、ローカルキャッシュファイルから読み取る。

## 技術メモ

### GNU coreutils 依存

`date -d "<ISO or @epoch>"` と `stat -c %Y` を使う。BSD 版は構文が異なるため、PATH 先頭に gnubin を差し込んで GNU 版を強制している。これがこのリポジトリが Windows 版と分かれている主因。

### bash の IFS=$'\t' read で空フィールドが圧縮される

```bash
IFS=$'\t' read -r a b c d e <<< "x\t\ty\tz"
# 期待: a=x, b="", c=y, d=z, e=""
# 実際: a=x, b=y, c=z, d="", e=""  ← 空フィールドが消える
```

bash は IFS が空白文字（space, tab, newline）の場合、連続を 1 つに圧縮する。複数値を TAB で渡すなら、空値を sentinel 文字（本実装では `-`）で置換してから join し、bash 側で復元する必要がある。jq の `nz()` ヘルパーがこれを担う。

### resets_at フィールド

stdin の JSON で `rate_limits.X.resets_at` は epoch 整数の場合と ISO 文字列の場合がある。`iso_epoch()` ヘルパーは両形式に対応している。

## ファイル構成

```
cc-mac-statusline/
├── README.md           # このファイル
├── LICENSE             # MIT
├── install.sh          # bash インストーラ
├── .gitignore
└── template/
    ├── settings.json   # statusLine 設定テンプレート
    └── statusline.sh   # 表示スクリプト本体
```

## カスタマイズ

`statusline.sh` 冒頭の色定義（`blue`, `green`, ...）や、レート制限バーの幅（`bar_width=10`）を変更すれば見た目を調整できる。1 行目 / 2 行目以降の構成は「LINE 1」セクションと「Rate limit lines」セクションで個別に組み立てている。

## ライセンス

MIT License. 詳細は [LICENSE](./LICENSE) を参照。
