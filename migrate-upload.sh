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
    if ! command -v unzip &> /dev/null; then
        apt-get update -qq && apt-get install -y -qq unzip > /dev/null 2>&1
    fi
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
# アップロード関数
# ------------------------------------------
upload_dir() {
    local name=$1
    local src=$2
    if [ -d "$src" ]; then
        # シンボリックリンクなら実体を辿る
        if [ -L "$src" ]; then
            src=$(readlink -f "$src")
        fi
        local count
        count=$(find "$src" -maxdepth 1 -type f \( -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.pth" -o -name "*.bin" \) 2>/dev/null | wc -l)
        if [ "$count" -gt 0 ]; then
            echo "[$name] $count ファイル検出 -> アップロード中..."
            rclone copy "$src/" "$GDRIVE_REMOTE:$GDRIVE_MIGRATION/$name/" \
                --include "*.safetensors" \
                --include "*.ckpt" \
                --include "*.pt" \
                --include "*.pth" \
                --include "*.bin" \
                -P --transfers 4
            echo "[$name] 完了"
            echo ""
            return 0
        fi
    fi
    return 1
}

# diffusers 用 (ディレクトリ単位)
upload_diffusers() {
    local name=$1
    local src=$2
    if [ -d "$src" ]; then
        if [ -L "$src" ]; then
            src=$(readlink -f "$src")
        fi
        local count
        count=$(find "$src" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
        if [ "$count" -gt 0 ]; then
            echo "[$name] $count ディレクトリ検出 -> アップロード中..."
            rclone copy "$src/" "$GDRIVE_REMOTE:$GDRIVE_MIGRATION/$name/" -P --transfers 4
            echo "[$name] 完了"
            echo ""
            return 0
        fi
    fi
    return 1
}

# ------------------------------------------
# 転送元の検出とアップロード
# ------------------------------------------
echo "転送元を検出中..."
echo "転送先: $GDRIVE_REMOTE:$GDRIVE_MIGRATION/"
echo ""

uploaded=0

# Checkpoints
upload_dir "checkpoints" "$NOTEBOOKS/models/checkpoints" || \
upload_dir "checkpoints" "$SD_DIR/models/Stable-diffusion" || \
echo "[checkpoints] 見つかりません (スキップ)"
[ $? -eq 0 ] || true
# 直前の upload_dir が成功したかチェック
rclone ls "$GDRIVE_REMOTE:$GDRIVE_MIGRATION/checkpoints/" 2>/dev/null | grep -q . && uploaded=1

# LoRA
upload_dir "loras" "$NOTEBOOKS/models/loras" || \
upload_dir "loras" "$SD_DIR/models/Lora" || \
echo "[loras] 見つかりません (スキップ)"
[ $? -eq 0 ] || true

# VAE
upload_dir "vae" "$NOTEBOOKS/models/vae" || \
upload_dir "vae" "$SD_DIR/models/VAE" || \
echo "[vae] 見つかりません (スキップ)"
[ $? -eq 0 ] || true

# ControlNet (本体)
upload_dir "controlnet" "$NOTEBOOKS/models/controlnet" || \
upload_dir "controlnet" "$SD_DIR/models/ControlNet" || \
echo "[controlnet] 見つかりません (スキップ)"
[ $? -eq 0 ] || true

# ControlNet (拡張機能内)
if [ -d "$SD_DIR/extensions/sd-webui-controlnet/models" ]; then
    upload_dir "controlnet-ext" "$SD_DIR/extensions/sd-webui-controlnet/models" || true
fi

# Embeddings
upload_dir "embeddings" "$NOTEBOOKS/models/embeddings" || \
upload_dir "embeddings" "$SD_DIR/embeddings" || \
upload_dir "embeddings" "$SD_DIR/models/embeddings" || \
echo "[embeddings] 見つかりません (スキップ)"
[ $? -eq 0 ] || true

# Upscalers
upload_dir "upscalers" "$NOTEBOOKS/models/upscalers" || \
upload_dir "upscalers" "$SD_DIR/models/ESRGAN" || \
echo "[upscalers] 見つかりません (スキップ)"
[ $? -eq 0 ] || true

# Diffusers
upload_diffusers "diffusers" "$NOTEBOOKS/models/diffusers" || \
upload_diffusers "diffusers" "$SD_DIR/models/diffusers" || true

# CLIP
upload_dir "clip" "$NOTEBOOKS/models/clip" || true

# UNet
upload_dir "unet" "$NOTEBOOKS/models/unet" || true

# ------------------------------------------
# 完了
# ------------------------------------------
echo "========================================"
echo "  アップロード完了!"
echo "========================================"
echo ""
echo "Google Drive 内の確認:"
rclone lsd "$GDRIVE_REMOTE:$GDRIVE_MIGRATION/" 2>/dev/null
echo ""
echo "詳細確認:"
echo "  rclone ls $GDRIVE_REMOTE:$GDRIVE_MIGRATION/ --max-depth 2"
echo ""
echo "次のステップ:"
echo "  1. 新しいプロジェクトを作成"
echo "  2. git clone https://github.com/ichikawa8219/paperspace-sd-setup.git"
echo "  3. bash paperspace-sd-setup/setup.sh"
echo "  4. bash paperspace-sd-setup/migrate-download.sh"
