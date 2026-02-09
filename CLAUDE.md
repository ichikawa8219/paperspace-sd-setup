# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Paperspace Gradient で Stable Diffusion WebUI (AUTOMATIC1111) と ComfyUI を効率的に運用するための Bash スクリプト集。モデル共有、複数インスタンス起動、Google Drive 同期を自動化する。

## Paperspace ストレージ構成

- `/notebooks/` — 永続ストレージ (50GB制限、$0.29/GB/月の超過料金)
- `/storage/` — チーム共有の永続ストレージ
- `/tmp/` — 一時領域 (セッション終了で消える)
- `/usr/local/lib/` — エフェメラル (セッション再起動でリセット)

## 核心アーキテクチャ

### モデル共有 (シンボリックリンク)

全モデルは `/notebooks/models/` に集約し、SD WebUI と ComfyUI からシンボリックリンクで参照する。`ln -sf` は既存ディレクトリの中にリンクを作るので、必ず `rm -rf` してから `ln -sf` する。

### ComfyUI 仮想環境

ComfyUI は `/notebooks/comfy-venv/` の独立した venv で実行。`--system-site-packages` は使わない（システム torch 2.1.1 と最新 ComfyUI が非互換のため）。起動時に `LD_LIBRARY_PATH` で venv 内の NVIDIA ライブラリを優先する。

### 一時モデル vs 永続モデル

- `/notebooks/models/` — SD WebUI 用の永続モデル (Civitai Helper 等でダウンロード)
- `/tmp/models/` — ComfyUI ワークフロー用の大型モデル (download.sh / workflows/*.sh)
- `extra_model_paths.yaml` で ComfyUI が両方を検索

### SD WebUI 複数インスタンス

`--data-dir` で設定・出力を分離。`sd-data-{1,2}/extensions` は本体の extensions へのシンボリックリンク。pip 競合回避のため SD #2 は SD #1 の gradio.live リンク確立後に起動。

## スクリプト関係図

```
setup.sh (初回1回)
  → モデルディレクトリ作成、リポジトリクローン、シンボリックリンク設定
  → ComfyUI venv 作成 + PyTorch(cu121) インストール
  → 拡張機能・rclone・cloudflared インストール

start.sh (毎セッション)
  → fix_system_deps: ml_dtypes 更新
  → fix_controlnet_deps: controlnet_aux パッチ (mediapipe_face 無効化)
  → fix_comfy_deps: venv + torch + requirements 確認
  → install_cloudflared: ComfyUI トンネル用
  → 起動 → wait_for_links: リンク検出・表示

download.sh — 対話式モデルダウンロード → /tmp/models/
workflows/*.sh — ワークフロー別モデル一括ダウンロード → /tmp/models/
sync.sh — 生成画像を Google Drive に転送
migrate-upload.sh / migrate-download.sh — プロジェクト間モデル移行
```

## 重要な変数・パス

| 変数 | パス | 用途 |
|------|------|------|
| `SD_DIR` | `/notebooks/stable-diffusion-webui` | SD WebUI 本体 |
| `COMFY_DIR` | `/notebooks/ComfyUI` | ComfyUI 本体 |
| `COMFY_VENV` | `/notebooks/comfy-venv` | ComfyUI 専用 venv |
| `MODELS_DIR` | `/notebooks/models` | 共有モデルディレクトリ |
| `SD_DATA_1/2` | `/notebooks/sd-data-{1,2}` | SD インスタンス別設定・出力 |
| `LOG_DIR` | `/notebooks/logs` | 起動ログ |
| `TMP_MODELS` | `/tmp/models` | 一時モデル (download.sh 用) |

## ポート

SD WebUI #1: 7860, SD WebUI #2: 7861, ComfyUI: 8188

## 既知の問題と対処パターン

- **svglib インストール失敗** — `libcairo2-dev` が未インストール。ControlNet の一部プリプロセッサが使えないが非致命的。
- **protobuf バージョン競合** — SD WebUI は 3.20.0 を要求、mediapipe は >=4.25.3 を要求。ControlNet の mediapipe_face を sed で無効化して回避。
- **gradio share リンク失敗** — ネットワーク競合時に発生。SD #2 の起動を SD #1 完了後まで遅延させて回避。
- **bilingual_localization_helper エラー** — `--data-dir` のシンボリックリンクパスと `Path.relative_to()` の非互換。非致命的（日本語化は動作する）。

## コード修正時の注意

- pip 出力を `-q 2>/dev/null` で抑制している箇所が多い。デバッグ時は一時的に外すこと。
- `set -e` は setup.sh のみ。start.sh は部分的な失敗を許容する設計。
- GitHub リポジトリは private。`rclone.conf` は gitignore 対象（認証トークンを含む）。
- ワークフロースクリプト (`workflows/*.sh`) の HuggingFace URL は変更される可能性がある。
