#!/bin/bash

# ============================================
#  移行スクリプト (2/2) - Google Drive からダウンロード
# ============================================
# 新しいプロジェクトで setup.sh の後に実行
# Google Drive に退避したモデルを戻す
#
# 使い方: bash migrate-download.sh

NOTEBOOKS="/notebooks"
MODELS_DIR="$NOTEBOOKS/models"
GDRIVE_REMOTE="gdrive"
GDRIVE_MIGRATION="SD_Migration"

echo "========================================"
echo "  移行ダウンロード"
echo "  Google Drive → 新プロジェクト"
echo "========================================"
echo ""

# ------------------------------------------
# 前提チェック
# ------------------------------------------
if [ ! -d "$MODELS_DIR/checkpoints" ]; then
    echo "エラー: $MODELS_DIR が見つかりません"
    echo "先に setup.sh を実行してください"
    exit 1
fi

# rclone チェック
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
# Google Drive の中身を確認
# ------------------------------------------
echo "Google Drive の移行データを確認中..."
echo ""

rclone lsd "$GDRIVE_REMOTE:$GDRIVE_MIGRATION/" 2>/dev/null
if [ $? -ne 0 ]; then
    echo "エラー: $GDRIVE_REMOTE:$GDRIVE_MIGRATION/ が見つかりません"
    echo "先に migrate-upload.sh を実行してください"
    exit 1
fi

echo ""

# 各ディレクトリのファイル数を表示
for dir_name in checkpoints loras vae controlnet embeddings upscalers diffusers clip unet; do
    count=$(rclone ls "$GDRIVE_REMOTE:$GDRIVE_MIGRATION/$dir_name/" 2>/dev/null | wc -l)
    if [ "$count" -gt 0 ]; then
        echo "  $dir_name: $count ファイル"
    fi
done

echo ""
read -r -p "ダウンロードを開始しますか? [y/N]: " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "中止しました"
    exit 0
fi

echo ""

# ------------------------------------------
# ダウンロード実行
# ------------------------------------------
download() {
    local name=$1
    local dst=$2
    # Google Drive にディレクトリが存在するか確認
    if rclone lsd "$GDRIVE_REMOTE:$GDRIVE_MIGRATION/$name" 2>/dev/null | grep -q . || \
       rclone ls "$GDRIVE_REMOTE:$GDRIVE_MIGRATION/$name/" 2>/dev/null | grep -q .; then
        echo "[$name] ダウンロード中..."
        mkdir -p "$dst"
        rclone copy "$GDRIVE_REMOTE:$GDRIVE_MIGRATION/$name/" "$dst/" -P --transfers 4
        echo "[$name] 完了"
        echo ""
    fi
}

download "checkpoints" "$MODELS_DIR/checkpoints"
download "loras" "$MODELS_DIR/loras"
download "vae" "$MODELS_DIR/vae"
download "controlnet" "$MODELS_DIR/controlnet"
download "embeddings" "$MODELS_DIR/embeddings"
download "upscalers" "$MODELS_DIR/upscalers"
download "diffusers" "$MODELS_DIR/diffusers"
download "clip" "$MODELS_DIR/clip"
download "unet" "$MODELS_DIR/unet"

# ------------------------------------------
# 完了
# ------------------------------------------
echo "========================================"
echo "  ダウンロード完了!"
echo "========================================"
echo ""
echo "モデル配置先: $MODELS_DIR/"
echo ""

# ストレージ使用量を表示
echo "ストレージ使用量:"
du -sh "$MODELS_DIR"/* 2>/dev/null
echo "---"
du -sh "$NOTEBOOKS"/* 2>/dev/null | sort -hr | head -10
echo "---"
echo "合計:"
du -sh "$NOTEBOOKS" 2>/dev/null

echo ""
echo "次のステップ:"
echo "  bash /notebooks/paperspace-sd-setup/start.sh"
echo ""
echo "(任意) Google Drive の移行データを削除:"
echo "  rclone purge $GDRIVE_REMOTE:$GDRIVE_MIGRATION/"
