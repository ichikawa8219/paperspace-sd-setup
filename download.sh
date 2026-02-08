#!/bin/bash

# ============================================
#  モデルダウンロードヘルパー
# ============================================
# 使い方:
#   bash download.sh <URL> <モデルタイプ>
#
# ComfyUI の「モデルが見つかりません」ダイアログで
# 「URLをコピー」→ ターミナルで実行
#
# 例:
#   bash download.sh "https://huggingface.co/.../vae.safetensors" vae
#   bash download.sh "https://huggingface.co/.../model.safetensors" lora
#   bash download.sh "https://huggingface.co/.../model.safetensors" diffusion_model
#
# モデルタイプ一覧:
#   vae, lora, checkpoint, controlnet, embedding, upscaler,
#   clip, unet, text_encoder, diffusion_model, diffusers

MODELS_DIR="/notebooks/models"

URL="$1"
TYPE="$2"

if [ -z "$URL" ] || [ -z "$TYPE" ]; then
    echo "使い方: bash download.sh <URL> <モデルタイプ>"
    echo ""
    echo "モデルタイプ:"
    echo "  vae              -> $MODELS_DIR/vae/"
    echo "  lora             -> $MODELS_DIR/loras/"
    echo "  checkpoint       -> $MODELS_DIR/checkpoints/"
    echo "  controlnet       -> $MODELS_DIR/controlnet/"
    echo "  embedding        -> $MODELS_DIR/embeddings/"
    echo "  upscaler         -> $MODELS_DIR/upscalers/"
    echo "  clip             -> $MODELS_DIR/clip/"
    echo "  unet             -> $MODELS_DIR/unet/"
    echo "  text_encoder     -> $MODELS_DIR/text_encoders/"
    echo "  diffusion_model  -> $MODELS_DIR/diffusion_models/"
    echo ""
    echo "例:"
    echo "  bash download.sh \"https://huggingface.co/.../model.safetensors\" vae"
    exit 1
fi

# モデルタイプ → ディレクトリのマッピング
case "$TYPE" in
    vae)
        DIR="$MODELS_DIR/vae" ;;
    lora|loras)
        DIR="$MODELS_DIR/loras" ;;
    checkpoint|checkpoints|ckpt)
        DIR="$MODELS_DIR/checkpoints" ;;
    controlnet)
        DIR="$MODELS_DIR/controlnet" ;;
    embedding|embeddings)
        DIR="$MODELS_DIR/embeddings" ;;
    upscaler|upscalers|upscale_models)
        DIR="$MODELS_DIR/upscalers" ;;
    clip)
        DIR="$MODELS_DIR/clip" ;;
    unet)
        DIR="$MODELS_DIR/unet" ;;
    text_encoder|text_encoders)
        DIR="$MODELS_DIR/text_encoders" ;;
    diffusion_model|diffusion_models)
        DIR="$MODELS_DIR/diffusion_models" ;;
    diffusers)
        DIR="$MODELS_DIR/diffusers" ;;
    *)
        echo "不明なモデルタイプ: $TYPE"
        echo "bash download.sh で使い方を確認してください"
        exit 1
        ;;
esac

mkdir -p "$DIR"

# URL からファイル名を取得 (クエリパラメータを除去)
FILENAME=$(basename "$URL" | sed 's/[?#].*//')

# ファイル名が空 or 拡張子なしの場合
if [ -z "$FILENAME" ] || ! echo "$FILENAME" | grep -q "\."; then
    echo "警告: ファイル名を URL から特定できません"
    read -r -p "ファイル名を入力: " FILENAME
fi

OUTPUT="$DIR/$FILENAME"

# 既にファイルが存在する場合
if [ -f "$OUTPUT" ]; then
    echo "既に存在: $OUTPUT"
    read -r -p "上書きしますか? [y/N]: " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "スキップしました"
        exit 0
    fi
fi

echo ""
echo "ダウンロード:"
echo "  URL:  $URL"
echo "  保存: $OUTPUT"
echo ""

wget --progress=bar:force -O "$OUTPUT" "$URL"

if [ $? -eq 0 ]; then
    size=$(du -h "$OUTPUT" | cut -f1)
    echo ""
    echo "完了: $OUTPUT ($size)"
else
    echo ""
    echo "エラー: ダウンロードに失敗しました"
    rm -f "$OUTPUT"
    exit 1
fi
