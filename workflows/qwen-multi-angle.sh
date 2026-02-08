#!/bin/bash

# ============================================
#  Qwen Image Edit - Multiple Angles モデルセット
# ============================================
# ComfyUI で Qwen Image Edit Multiple Angles ワークフローを
# 使うために必要なモデルを一括ダウンロード
#
# ダウンロード先: /tmp/models/ (一時領域・セッション終了で消える)
# 合計サイズ: 約 30GB
#
# 使い方:
#   bash workflows/qwen-multi-angle.sh

TMP_MODELS="/tmp/models"

echo "========================================"
echo "  Qwen Image Edit - Multiple Angles"
echo "  モデル一括ダウンロード"
echo "========================================"
echo ""
echo "ダウンロード先: $TMP_MODELS/ (一時領域)"
echo ""

# ダウンロード関数
dl() {
    local url="$1"
    local dir="$2"
    local filename
    filename=$(basename "$url" | sed 's/[?#].*//')

    mkdir -p "$dir"

    if [ -f "$dir/$filename" ]; then
        local size
        size=$(du -h "$dir/$filename" | cut -f1)
        echo "  [スキップ] $filename ($size) - 既にダウンロード済み"
        return 0
    fi

    echo "  [DL] $filename -> $dir/"
    wget -q --show-progress -O "$dir/$filename" "$url"
    if [ $? -ne 0 ]; then
        echo "  [エラー] $filename のダウンロードに失敗"
        rm -f "$dir/$filename"
        return 1
    fi
}

# ------------------------------------------
# 1. 拡散モデル (Diffusion Model) ~20GB
# ------------------------------------------
echo "[1/5] 拡散モデル"
dl "https://huggingface.co/Comfy-Org/Qwen-Image-Edit_ComfyUI/resolve/main/split_files/diffusion_models/qwen_image_edit_2511_bf16.safetensors" \
    "$TMP_MODELS/diffusion_models"

# ------------------------------------------
# 2. LoRA - Lightning 4steps
# ------------------------------------------
echo "[2/5] LoRA (Lightning 4steps)"
dl "https://huggingface.co/lightx2v/Qwen-Image-Edit-2511-Lightning/resolve/main/Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors" \
    "$TMP_MODELS/loras"

# ------------------------------------------
# 3. LoRA - Multiple Angles (~295MB)
# ------------------------------------------
echo "[3/5] LoRA (Multiple Angles)"
dl "https://huggingface.co/fal/Qwen-Image-Edit-2511-Multiple-Angles-LoRA/resolve/main/qwen-image-edit-2511-multiple-angles-lora.safetensors" \
    "$TMP_MODELS/loras"

# ------------------------------------------
# 4. CLIP / Text Encoder (~9.4GB)
# ------------------------------------------
echo "[4/5] CLIP / Text Encoder"
dl "https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors" \
    "$TMP_MODELS/text_encoders"

# ------------------------------------------
# 5. VAE (~254MB)
# ------------------------------------------
echo "[5/5] VAE"
dl "https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/vae/qwen_image_vae.safetensors" \
    "$TMP_MODELS/vae"

# ------------------------------------------
# 完了
# ------------------------------------------
echo ""
echo "========================================"
echo "  ダウンロード完了"
echo "========================================"
echo ""
echo "ファイル一覧:"
for dir in diffusion_models loras text_encoders vae; do
    if [ -d "$TMP_MODELS/$dir" ]; then
        for f in "$TMP_MODELS/$dir"/*.safetensors; do
            [ -f "$f" ] && echo "  $(du -h "$f" | cut -f1)  $f"
        done
    fi
done
echo ""
echo "ComfyUI で Qwen Image Edit Multiple Angles ワークフローを読み込んでください"
