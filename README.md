# Paperspace SD Setup

Paperspace Gradient で Stable Diffusion WebUI / ComfyUI を効率的に運用するためのスクリプト集。

## 特徴

- **SD WebUI + ComfyUI の同時起動** (A6000 48GB VRAM で余裕)
- **SD WebUI × 2 の同時起動** (`--data-dir` で設定分離)
- **モデル共有**: シンボリックリンクでストレージ節約
- **Google Drive 同期**: 生成画像を自動転送してストレージ確保
- **ワンコマンド起動**: 引数 or メニューで起動構成を選択

## Paperspace ディレクトリ構成

```
/
├── notebooks/          ← ノートブック専用の永続ストレージ (50GB制限)
├── storage/            ← チーム共有の永続ストレージ
├── tmp/                ← 一時領域 (セッション終了で消える)
└── datasets/           ← データセットマウント用
```

## セットアップ後の構成 (/notebooks 内)

```
/notebooks/
├── models/                      ← モデル共通置き場 (シンボリックリンク元)
│   ├── checkpoints/
│   ├── loras/
│   ├── vae/
│   ├── embeddings/
│   ├── controlnet/
│   ├── upscalers/
│   ├── diffusers/               ← HuggingFace diffusers 形式モデル
│   ├── clip/
│   └── unet/
├── stable-diffusion-webui/      ← SD WebUI 本体 (モデルはシンボリックリンク)
├── ComfyUI/                     ← ComfyUI 本体 (モデルはシンボリックリンク)
├── sd-data-1/                   ← SD インスタンス1 の設定・出力
├── sd-data-2/                   ← SD インスタンス2 の設定・出力
├── logs/                        ← 起動ログ
├── rclone.conf                  ← rclone 設定 (永続保存・gitignore対象)
└── paperspace-sd-setup/         ← このリポジトリ
```

## セットアップ (初回のみ)

```bash
# 1. リポジトリをクローン
cd /notebooks
git clone https://github.com/YOUR_USERNAME/paperspace-sd-setup.git

# 2. セットアップ実行
bash paperspace-sd-setup/setup.sh
# -> 既存の SD WebUI のモデルを /notebooks/models/ に移動
# -> ComfyUI をインストール
# -> シンボリックリンクを設定

# 3. モデルの確認
ls -la /notebooks/models/checkpoints/

# 4. (任意) rclone で Google Drive を設定
rclone config
# -> "n" -> 名前: gdrive -> タイプ: drive -> ブラウザ認証
# 設定を永続保存:
cp ~/.config/rclone/rclone.conf /notebooks/rclone.conf
```

## 起動 (毎セッション)

### メニューから選択

```bash
bash /notebooks/paperspace-sd-setup/start.sh
```

```
========================================
  Paperspace SD Launcher
========================================

  1) SD WebUI のみ
  2) ComfyUI のみ
  3) SD WebUI + ComfyUI
  4) SD WebUI x 2
  5) SD WebUI x 2 + ComfyUI

選択 [1-5]:
```

### 引数で直接起動

```bash
# SD WebUI のみ
bash /notebooks/paperspace-sd-setup/start.sh sd

# ComfyUI のみ
bash /notebooks/paperspace-sd-setup/start.sh comfy

# SD WebUI + ComfyUI
bash /notebooks/paperspace-sd-setup/start.sh sd comfy

# SD WebUI × 2
bash /notebooks/paperspace-sd-setup/start.sh sd sd

# SD WebUI × 2 + ComfyUI
bash /notebooks/paperspace-sd-setup/start.sh sd sd comfy
```

## ポート一覧

| サービス | ポート |
|---------|--------|
| SD WebUI #1 | 7860 |
| SD WebUI #2 | 7861 |
| ComfyUI | 8188 |

起動後、`--share` で生成される Gradio リンク (`https://xxxxx.gradio.live`) からアクセスできます。

## Google Drive 同期

セッション終了前に実行して、生成画像を Google Drive に退避します。

```bash
# 画像を転送 & ローカル削除 (容量確保)
bash /notebooks/paperspace-sd-setup/sync.sh

# 画像を転送のみ (ローカルにも残す)
bash /notebooks/paperspace-sd-setup/sync.sh --keep

# ストレージ使用量を確認
bash /notebooks/paperspace-sd-setup/sync.sh --status
```

転送先: `Google Drive > SD_Backup > YYYYMMDD > (sd-1 / sd-2 / comfyui)`

## VRAM 使用量の目安 (A6000 48GB)

| 構成 | VRAM 消費 | 残り |
|------|----------|------|
| SD WebUI × 1 (SDXL) | ~6-8GB | ~40GB |
| SD WebUI + ComfyUI | ~12-16GB | ~32GB |
| SD WebUI × 2 | ~12-16GB | ~32GB |
| SD WebUI × 2 + ComfyUI | ~18-24GB | ~24GB |

48GB あればどの構成でも余裕です。

## よく使うコマンド

```bash
# ログ確認
tail -f /notebooks/logs/sd-1.log
tail -f /notebooks/logs/comfy.log

# プロセス確認
ps aux | grep -E "launch.py|main.py"

# 全プロセス停止
kill $(ps aux | grep -E "launch.py|main.py" | grep -v grep | awk '{print $2}')

# ストレージ確認
du -sh /notebooks/*
```

## 注意事項

- `rclone.conf` には Google Drive の認証トークンが含まれます。**リポジトリにコミットしないでください**
- Paperspace のセッションは最長6時間です。終了前に `sync.sh` を実行してください
- `/notebooks/` の容量上限は 50GB (Glow プラン) です。定期的に `sync.sh --status` で確認してください
- 50GB を超過すると $0.29/GB/月 の追加料金が発生します
