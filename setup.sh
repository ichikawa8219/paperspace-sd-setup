#!/bin/bash
set -e

# ============================================
#  Paperspace SD Setup - 初回セットアップ
# ============================================
# 使い方: bash setup.sh
# Paperspace Gradient ノートブックのターミナルで1回だけ実行
#
# Paperspace ディレクトリ構成:
#   /notebooks/  → ノートブック専用の永続ストレージ (50GB制限)
#   /storage/    → チーム共有の永続ストレージ
#   /tmp/        → 一時領域 (セッション終了で消える)

NOTEBOOKS="/notebooks"
STORAGE="/storage"
MODELS_DIR="$NOTEBOOKS/models"
SD_DIR="$NOTEBOOKS/stable-diffusion-webui"
COMFY_DIR="$NOTEBOOKS/ComfyUI"
SD_DATA_1="$NOTEBOOKS/sd-data-1"
SD_DATA_2="$NOTEBOOKS/sd-data-2"

echo "========================================"
echo "  Paperspace SD Setup - 初回セットアップ"
echo "========================================"
echo ""

# ------------------------------------------
# 1. 共有モデルディレクトリの作成
# ------------------------------------------
echo "[1/6] 共有モデルディレクトリを作成中..."
mkdir -p "$MODELS_DIR/checkpoints"
mkdir -p "$MODELS_DIR/loras"
mkdir -p "$MODELS_DIR/vae"
mkdir -p "$MODELS_DIR/embeddings"
mkdir -p "$MODELS_DIR/controlnet"
mkdir -p "$MODELS_DIR/upscalers"
mkdir -p "$MODELS_DIR/diffusers"
mkdir -p "$MODELS_DIR/clip"
mkdir -p "$MODELS_DIR/unet"
echo "  -> $MODELS_DIR に作成完了"

# ------------------------------------------
# 2. Stable Diffusion WebUI
# ------------------------------------------
echo ""
echo "[2/6] Stable Diffusion WebUI を確認中..."
if [ -d "$SD_DIR" ]; then
    echo "  -> 既にインストール済み: $SD_DIR"
else
    git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git "$SD_DIR"
    echo "  -> インストール完了"
fi

# 既存のモデルを共有ディレクトリに移動 (まだシンボリックリンクでなければ)
echo "  -> 既存モデルファイルの移動中..."
for pair in \
    "Stable-diffusion:checkpoints" \
    "Lora:loras" \
    "VAE:vae" \
    "ControlNet:controlnet" \
    "ESRGAN:upscalers"; do
    sd_name="${pair%%:*}"
    shared_name="${pair##*:}"
    src="$SD_DIR/models/$sd_name"
    dst="$MODELS_DIR/$shared_name"
    if [ -d "$src" ] && [ ! -L "$src" ]; then
        count=$(find "$src" -maxdepth 1 -type f \( -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.pth" -o -name "*.bin" \) 2>/dev/null | wc -l)
        if [ "$count" -gt 0 ]; then
            echo "    $sd_name -> $dst ($count ファイル移動)"
            find "$src" -maxdepth 1 -type f \( -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.pth" -o -name "*.bin" \) \
                -exec mv -n {} "$dst/" \; 2>/dev/null || true
        else
            echo "    $sd_name -> 移動するファイルなし"
        fi
    fi
done
# embeddings は models の外にもある
if [ -d "$SD_DIR/embeddings" ] && [ ! -L "$SD_DIR/embeddings" ]; then
    count=$(find "$SD_DIR/embeddings" -maxdepth 1 -type f \( -name "*.safetensors" -o -name "*.pt" -o -name "*.bin" \) 2>/dev/null | wc -l)
    if [ "$count" -gt 0 ]; then
        echo "    embeddings -> $MODELS_DIR/embeddings ($count ファイル移動)"
        find "$SD_DIR/embeddings" -maxdepth 1 -type f \( -name "*.safetensors" -o -name "*.pt" -o -name "*.bin" \) \
            -exec mv -n {} "$MODELS_DIR/embeddings/" \; 2>/dev/null || true
    fi
fi
# diffusers はディレクトリ単位で管理される (model_index.json + サブフォルダ)
for diffusers_src in "$SD_DIR/models/diffusers" "$COMFY_DIR/models/diffusers"; do
    if [ -d "$diffusers_src" ] && [ ! -L "$diffusers_src" ]; then
        for model_dir in "$diffusers_src"/*/; do
            [ -d "$model_dir" ] || continue
            dir_name=$(basename "$model_dir")
            if [ ! -e "$MODELS_DIR/diffusers/$dir_name" ]; then
                echo "    diffusers/$dir_name -> $MODELS_DIR/diffusers/ (ディレクトリ移動)"
                mv -n "$model_dir" "$MODELS_DIR/diffusers/" 2>/dev/null || true
            fi
        done
    fi
done

# SD WebUI のモデルディレクトリをシンボリックリンクに置換
echo "  -> モデルのシンボリックリンクを設定中..."
for pair in \
    "Stable-diffusion:checkpoints" \
    "Lora:loras" \
    "VAE:vae" \
    "embeddings:embeddings" \
    "ControlNet:controlnet" \
    "ESRGAN:upscalers" \
    "diffusers:diffusers"; do
    sd_name="${pair%%:*}"
    shared_name="${pair##*:}"
    target="$SD_DIR/models/$sd_name"
    if [ -L "$target" ]; then
        echo "    $sd_name -> 既にリンク済み (スキップ)"
    else
        rm -rf "$target"
        ln -sf "$MODELS_DIR/$shared_name" "$target"
        echo "    $sd_name -> $MODELS_DIR/$shared_name"
    fi
done
# embeddings は models の外にもある
if [ -L "$SD_DIR/embeddings" ]; then
    echo "    embeddings (root) -> 既にリンク済み (スキップ)"
else
    rm -rf "$SD_DIR/embeddings"
    ln -sf "$MODELS_DIR/embeddings" "$SD_DIR/embeddings"
    echo "    embeddings (root) -> $MODELS_DIR/embeddings"
fi

# ------------------------------------------
# 3. SD WebUI 拡張機能のインストール
# ------------------------------------------
echo ""
echo "[3/6] SD WebUI 拡張機能をインストール中..."
EXTENSIONS_DIR="$SD_DIR/extensions"
mkdir -p "$EXTENSIONS_DIR"

extensions=(
    "Bing-su/adetailer"
    "zixaphir/Stable-Diffusion-Webui-Civitai-Helper"
    "adieyal/sd-dynamic-prompts"
    "Mikubill/sd-webui-controlnet"
    "AI-Creators-Society/stable-diffusion-webui-localization-ja_JP"
    "AlUlkesh/stable-diffusion-webui-images-browser"
    "picobyte/stable-diffusion-webui-wd14-tagger"
)

for ext in "${extensions[@]}"; do
    ext_name="${ext##*/}"
    if [ -d "$EXTENSIONS_DIR/$ext_name" ]; then
        echo "    $ext_name -> 既にインストール済み (スキップ)"
    else
        echo "    $ext_name -> インストール中..."
        git clone "https://github.com/$ext" "$EXTENSIONS_DIR/$ext_name" --quiet
    fi
done

# ------------------------------------------
# 4. ComfyUI のインストール
# ------------------------------------------
echo ""
echo "[4/6] ComfyUI をインストール中..."
if [ -d "$COMFY_DIR" ]; then
    echo "  -> 既にインストール済み: $COMFY_DIR (スキップ)"
else
    git clone https://github.com/comfyanonymous/ComfyUI.git "$COMFY_DIR"
    echo "  -> インストール完了"
fi

# ComfyUI のモデルディレクトリをシンボリックリンクに置換
echo "  -> モデルのシンボリックリンクを設定中..."
for pair in \
    "checkpoints:checkpoints" \
    "loras:loras" \
    "vae:vae" \
    "embeddings:embeddings" \
    "controlnet:controlnet" \
    "upscale_models:upscalers" \
    "diffusers:diffusers" \
    "clip:clip" \
    "unet:unet"; do
    comfy_name="${pair%%:*}"
    shared_name="${pair##*:}"
    target="$COMFY_DIR/models/$comfy_name"
    if [ -L "$target" ]; then
        echo "    $comfy_name -> 既にリンク済み (スキップ)"
    else
        rm -rf "$target"
        ln -sf "$MODELS_DIR/$shared_name" "$target"
        echo "    $comfy_name -> $MODELS_DIR/$shared_name"
    fi
done

# ------------------------------------------
# 4. SD WebUI 用 data-dir の作成
# ------------------------------------------
echo ""
echo "[5/6] SD WebUI の data-dir を作成中..."
mkdir -p "$SD_DATA_1"
mkdir -p "$SD_DATA_2"
# data-dir から拡張機能を参照できるようにシンボリックリンクを作成
for data_dir in "$SD_DATA_1" "$SD_DATA_2"; do
    if [ -L "$data_dir/extensions" ]; then
        echo "  -> $data_dir/extensions -> 既にリンク済み (スキップ)"
    else
        rm -rf "$data_dir/extensions"
        ln -sf "$SD_DIR/extensions" "$data_dir/extensions"
        echo "  -> $data_dir/extensions -> $SD_DIR/extensions"
    fi
done
echo "  -> $SD_DATA_1 (インスタンス1)"
echo "  -> $SD_DATA_2 (インスタンス2)"

# ------------------------------------------
# 5. rclone のインストール
# ------------------------------------------
echo ""
echo "[6/6] rclone をインストール中..."
if command -v rclone &> /dev/null; then
    echo "  -> 既にインストール済み (スキップ)"
else
    # rclone のインストーラーに unzip が必要
    if ! command -v unzip &> /dev/null; then
        echo "  -> unzip をインストール中..."
        apt-get update -qq && apt-get install -y -qq unzip > /dev/null 2>&1
    fi
    curl -s https://rclone.org/install.sh | bash
    echo "  -> インストール完了"
fi

# ------------------------------------------
# 完了
# ------------------------------------------
echo ""
echo "========================================"
echo "  セットアップ完了!"
echo "========================================"
echo ""
echo "ディレクトリ構成:"
echo "  $NOTEBOOKS/"
echo "  ├── models/              <- モデル共通置き場"
echo "  │   ├── checkpoints/"
echo "  │   ├── loras/"
echo "  │   ├── vae/"
echo "  │   ├── embeddings/"
echo "  │   ├── controlnet/"
echo "  │   └── upscalers/"
echo "  ├── stable-diffusion-webui/  <- SD WebUI (モデルはシンボリックリンク)"
echo "  ├── ComfyUI/                 <- ComfyUI (モデルはシンボリックリンク)"
echo "  ├── sd-data-1/               <- SD インスタンス1 設定・出力"
echo "  └── sd-data-2/               <- SD インスタンス2 設定・出力"
echo ""
echo "次のステップ:"
echo "  1. モデルが $MODELS_DIR/checkpoints/ に移動されたか確認"
echo "     ls -la $MODELS_DIR/checkpoints/"
echo "  2. (任意) rclone の Google Drive 設定:"
echo "     rclone config"
echo "     -> 設定後: cp ~/.config/rclone/rclone.conf $NOTEBOOKS/rclone.conf"
echo "  3. 起動: bash start.sh"
echo ""
echo "ストレージ使用量:"
du -sh "$NOTEBOOKS"/* 2>/dev/null | head -20
echo "---"
du -sh "$STORAGE"/* 2>/dev/null | head -20
