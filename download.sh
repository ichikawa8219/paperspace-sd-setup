#!/bin/bash

# ============================================
#  モデルダウンロードヘルパー (ComfyUI 用)
# ============================================
# 使い方:
#   bash download.sh <URL> <モデルタイプ>
#
# ComfyUI の「モデルが見つかりません」ダイアログで
# 「URLをコピー」→ ターミナルで実行
#
# ダウンロード先: /tmp/models/<タイプ>/ (一時領域・セッション終了で消える)
# ComfyUI は extra_model_paths.yaml で /tmp/models/ も検索するよう設定済み
#
# 例:
#   bash download.sh "https://huggingface.co/.../vae.safetensors" vae
#   bash download.sh "https://huggingface.co/.../model.safetensors" lora
#   bash download.sh "https://huggingface.co/.../model.safetensors" diffusion_model
#
# モデルタイプ一覧:
#   vae, lora, checkpoint, controlnet, embedding, upscaler,
#   clip, unet, text_encoder, diffusion_model

TMP_MODELS="/tmp/models"

URL="$1"
TYPE="$2"

if [ -z "$URL" ] || [ -z "$TYPE" ]; then
    echo "使い方: bash download.sh <URL> <モデルタイプ>"
    echo ""
    echo "ダウンロード先: $TMP_MODELS/<タイプ>/ (一時領域)"
    echo ""
    echo "モデルタイプ:"
    echo "  vae              -> $TMP_MODELS/vae/"
    echo "  lora             -> $TMP_MODELS/loras/"
    echo "  checkpoint       -> $TMP_MODELS/checkpoints/"
    echo "  controlnet       -> $TMP_MODELS/controlnet/"
    echo "  embedding        -> $TMP_MODELS/embeddings/"
    echo "  upscaler         -> $TMP_MODELS/upscalers/"
    echo "  clip             -> $TMP_MODELS/clip/"
    echo "  unet             -> $TMP_MODELS/unet/"
    echo "  text_encoder     -> $TMP_MODELS/text_encoders/"
    echo "  diffusion_model  -> $TMP_MODELS/diffusion_models/"
    echo ""
    echo "例:"
    echo "  bash download.sh \"https://huggingface.co/.../model.safetensors\" vae"
    exit 1
fi

# モデルタイプ → サブディレクトリのマッピング
case "$TYPE" in
    vae)
        SUBDIR="vae" ;;
    lora|loras)
        SUBDIR="loras" ;;
    checkpoint|checkpoints|ckpt)
        SUBDIR="checkpoints" ;;
    controlnet)
        SUBDIR="controlnet" ;;
    embedding|embeddings)
        SUBDIR="embeddings" ;;
    upscaler|upscalers|upscale_models)
        SUBDIR="upscalers" ;;
    clip)
        SUBDIR="clip" ;;
    unet)
        SUBDIR="unet" ;;
    text_encoder|text_encoders)
        SUBDIR="text_encoders" ;;
    diffusion_model|diffusion_models)
        SUBDIR="diffusion_models" ;;
    *)
        echo "不明なモデルタイプ: $TYPE"
        echo "bash download.sh で使い方を確認してください"
        exit 1
        ;;
esac

DIR="$TMP_MODELS/$SUBDIR"
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
echo "  保存: $OUTPUT (一時領域)"
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
