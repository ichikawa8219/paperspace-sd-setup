#!/bin/bash

# ============================================
#  移行スクリプト (1/2) - Google Drive にアップロード
# ============================================
# 現在のプロジェクトで実行
# モデルと LoRA を Google Drive に退避する
#
# 使い方: bash migrate-upload.sh

NOTEBOOKS="/notebooks"
SD_DIR="$NOTEBOOKS/stable-diffusion-webui"
GDRIVE_REMOTE="gdrive"
GDRIVE_MIGRATION="SD_Migration"

echo "========================================"
echo "  移行アップロード"
echo "  現プロジェクト → Google Drive"
echo "========================================"
echo ""

# ------------------------------------------
# rclone チェック
# ------------------------------------------
if ! command -v rclone &> /dev/null; then
    echo "rclone がインストールされていません。インストールします..."
    curl -s https://rclone.org/install.sh | bash
fi

# rclone 設定の復元
if [ -f "$NOTEBOOKS/rclone.conf" ]; then
    mkdir -p ~/.config/rclone
    cp "$NOTEBOOKS/rclone.conf" ~/.config/rclone/rclone.conf
    echo "[rclone] 設定を復元しました"
fi

if ! rclone listremotes 2>/dev/null | grep -q "^${GDRIVE_REMOTE}:"; then
    echo "エラー: rclone に '$GDRIVE_REMOTE' リモートが設定されていません"
    echo ""
    echo "先に設定してください:"
    echo "  rclone config"
    echo "  -> 'n' -> 名前: gdrive -> タイプ: drive -> ブラウザ認証"
    echo "  設定後: cp ~/.config/rclone/rclone.conf $NOTEBOOKS/rclone.conf"
    exit 1
fi

# ------------------------------------------
# 転送元の検出
# ------------------------------------------
echo "転送元を検出中..."
echo ""

# モデルの場所を探す (シンボリックリンク先 or 直接配置)
find_models_dir() {
    local name=$1
    local candidates=("$@")
    shift 1
    for dir in "$@"; do
        # シンボリックリンクなら実体を辿る
        if [ -L "$dir" ]; then
            dir=$(readlink -f "$dir")
        fi
        if [ -d "$dir" ]; then
            local count
            count=$(find "$dir" -maxdepth 1 -type f \( -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.pth" -o -name "*.bin" \) 2>/dev/null | wc -l)
            if [ "$count" -gt 0 ]; then
                echo "  $name: $dir ($count ファイル)"
                echo "$dir"
                return 0
            fi
        fi
    done
    echo "  $name: 見つかりません" >&2
    return 1
}

# diffusers モデルの検出
find_diffusers_dir() {
    local name=$1
    shift 1
    for dir in "$@"; do
        if [ -L "$dir" ]; then
            dir=$(readlink -f "$dir")
        fi
        if [ -d "$dir" ]; then
            local count
            count=$(find "$dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
            if [ "$count" -gt 0 ]; then
                echo "  $name: $dir ($count ディレクトリ)" >&2
                echo "$dir"
                return 0
            fi
        fi
    done
    echo "  $name: 見つかりません" >&2
    return 1
}

# 各モデルタイプの場所を検出
CKPT_DIR=$(find_models_dir "checkpoints" \
    "$NOTEBOOKS/models/checkpoints" \
    "$SD_DIR/models/Stable-diffusion" \
    2>/dev/null) || true

LORA_DIR=$(find_models_dir "loras" \
    "$NOTEBOOKS/models/loras" \
    "$SD_DIR/models/Lora" \
    2>/dev/null) || true

VAE_DIR=$(find_models_dir "vae" \
    "$NOTEBOOKS/models/vae" \
    "$SD_DIR/models/VAE" \
    2>/dev/null) || true

CN_DIR=$(find_models_dir "controlnet" \
    "$NOTEBOOKS/models/controlnet" \
    "$SD_DIR/models/ControlNet" \
    2>/dev/null) || true

EMB_DIR=$(find_models_dir "embeddings" \
    "$NOTEBOOKS/models/embeddings" \
    "$SD_DIR/embeddings" \
    "$SD_DIR/models/embeddings" \
    2>/dev/null) || true

UPSCALER_DIR=$(find_models_dir "upscalers" \
    "$NOTEBOOKS/models/upscalers" \
    "$SD_DIR/models/ESRGAN" \
    2>/dev/null) || true

DIFFUSERS_DIR=$(find_diffusers_dir "diffusers" \
    "$NOTEBOOKS/models/diffusers" \
    "$SD_DIR/models/diffusers" \
    2>/dev/null) || true

CLIP_DIR=$(find_models_dir "clip" \
    "$NOTEBOOKS/models/clip" \
    2>/dev/null) || true

UNET_DIR=$(find_models_dir "unet" \
    "$NOTEBOOKS/models/unet" \
    2>/dev/null) || true

echo ""

# ------------------------------------------
# アップロード確認
# ------------------------------------------
echo "転送先: $GDRIVE_REMOTE:$GDRIVE_MIGRATION/"
echo ""
read -r -p "Google Drive にアップロードを開始しますか? [y/N]: " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "中止しました"
    exit 0
fi

echo ""

# ------------------------------------------
# アップロード実行
# ------------------------------------------
upload() {
    local name=$1
    local src=$2
    if [ -n "$src" ] && [ -d "$src" ]; then
        echo "[$name] アップロード中..."
        rclone copy "$src/" "$GDRIVE_REMOTE:$GDRIVE_MIGRATION/$name/" -P --transfers 4
        echo "[$name] 完了"
        echo ""
    fi
}

upload "checkpoints" "$CKPT_DIR"
upload "loras" "$LORA_DIR"
upload "vae" "$VAE_DIR"
upload "controlnet" "$CN_DIR"
upload "embeddings" "$EMB_DIR"
upload "upscalers" "$UPSCALER_DIR"
upload "diffusers" "$DIFFUSERS_DIR"
upload "clip" "$CLIP_DIR"
upload "unet" "$UNET_DIR"

# ------------------------------------------
# 完了
# ------------------------------------------
echo "========================================"
echo "  アップロード完了!"
echo "========================================"
echo ""
echo "Google Drive 内:"
echo "  $GDRIVE_REMOTE:$GDRIVE_MIGRATION/"
echo ""
echo "確認コマンド:"
echo "  rclone ls $GDRIVE_REMOTE:$GDRIVE_MIGRATION/ --max-depth 2"
echo ""
echo "次のステップ:"
echo "  1. 新しいプロジェクトを作成"
echo "  2. git clone https://TOKEN@github.com/ichikawa8219/paperspace-sd-setup.git"
echo "  3. bash paperspace-sd-setup/setup.sh"
echo "  4. bash paperspace-sd-setup/migrate-download.sh"
