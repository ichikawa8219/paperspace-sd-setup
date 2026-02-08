#!/bin/bash

# ============================================
#  モデルダウンロードヘルパー (ComfyUI 用)
# ============================================
# 使い方:
#   bash download.sh
#   → 対話形式で URL とモデルタイプを入力
#
# ダウンロード先: /tmp/models/<タイプ>/ (一時領域・セッション終了で消える)
# ComfyUI は extra_model_paths.yaml で /tmp/models/ も検索するよう設定済み

TMP_MODELS="/tmp/models"

echo "========================================"
echo "  モデルダウンロードヘルパー"
echo "========================================"
echo ""

# Step 1: URL 入力
read -r -p "ダウンロード URL: " URL

if [ -z "$URL" ]; then
    echo "URL が入力されていません"
    exit 1
fi

# Step 2: モデルタイプ選択
echo ""
echo "モデルタイプを選択してください:"
echo ""
echo "  1) vae"
echo "  2) text_encoder"
echo "  3) diffusion_model"
echo "  4) lora"
echo "  5) checkpoint"
echo "  6) controlnet"
echo "  7) clip"
echo "  8) unet"
echo "  9) embedding"
echo ""
read -r -p "選択 [1-9]: " choice

case "$choice" in
    1) SUBDIR="vae" ;;
    2) SUBDIR="text_encoders" ;;
    3) SUBDIR="diffusion_models" ;;
    4) SUBDIR="loras" ;;
    5) SUBDIR="checkpoints" ;;
    6) SUBDIR="controlnet" ;;
    7) SUBDIR="clip" ;;
    8) SUBDIR="unet" ;;
    9) SUBDIR="embeddings" ;;
    *)
        echo "無効な選択です"
        exit 1
        ;;
esac

DIR="$TMP_MODELS/$SUBDIR"
mkdir -p "$DIR"

# URL からファイル名を取得 (クエリパラメータを除去)
FILENAME=$(basename "$URL" | sed 's/[?#].*//')

# ファイル名が空 or 拡張子なしの場合
if [ -z "$FILENAME" ] || ! echo "$FILENAME" | grep -q "\."; then
    echo ""
    echo "警告: ファイル名を URL から特定できません"
    read -r -p "ファイル名を入力: " FILENAME
fi

OUTPUT="$DIR/$FILENAME"

# 既にファイルが存在する場合
if [ -f "$OUTPUT" ]; then
    echo ""
    echo "既に存在: $OUTPUT"
    read -r -p "上書きしますか? [y/N]: " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "スキップしました"
        exit 0
    fi
fi

echo ""
echo "----------------------------------------"
echo "  URL:  $URL"
echo "  保存: $OUTPUT"
echo "----------------------------------------"
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
