#!/bin/bash

# ============================================
#  Paperspace SD Sync - Google Drive 同期
# ============================================
# 使い方:
#   bash sync.sh            → 生成画像をGDriveに転送＆ローカル削除
#   bash sync.sh --keep     → 転送のみ（ローカル画像を残す）
#   bash sync.sh --status   → ストレージ使用量を表示
#
# Paperspace ディレクトリ構成:
#   /notebooks/  → ノートブック専用の永続ストレージ (50GB制限)
#   /storage/    → チーム共有の永続ストレージ
#   /tmp/        → 一時領域 (セッション終了で消える)

NOTEBOOKS="/notebooks"
SD_DATA_1="$NOTEBOOKS/sd-data-1"
SD_DATA_2="$NOTEBOOKS/sd-data-2"
COMFY_DIR="$NOTEBOOKS/ComfyUI"
GDRIVE_REMOTE="gdrive"
GDRIVE_BASE="SD_Backup"
TODAY=$(TZ='Asia/Tokyo' date +%Y%m%d)

# ------------------------------------------
# 転送先フォルダ名を決定（重複時はナンバリング）
# ------------------------------------------
resolve_dest_dir() {
    local existing
    existing=$(rclone lsd "$GDRIVE_REMOTE:$GDRIVE_BASE/" 2>/dev/null | awk '{print $NF}')

    if echo "$existing" | grep -q "^${TODAY}$"; then
        # 同日フォルダが既に存在 → ナンバリング
        local num=2
        while echo "$existing" | grep -q "^${TODAY}-${num}$"; do
            num=$((num + 1))
        done
        echo "${TODAY}-${num}"
    else
        echo "${TODAY}"
    fi
}

# ------------------------------------------
# ストレージ使用量の表示
# ------------------------------------------
show_status() {
    echo "========================================"
    echo "  ストレージ使用量"
    echo "========================================"
    echo ""
    echo "[/notebooks]"
    du -sh "$NOTEBOOKS"/* 2>/dev/null | sort -hr
    echo ""
    echo "合計 (/notebooks):"
    du -sh "$NOTEBOOKS" 2>/dev/null
    echo ""

    # 画像ファイル数をカウント
    local count=0
    for dir in "$SD_DATA_1/outputs" "$SD_DATA_2/outputs" "$COMFY_DIR/output"; do
        if [ -d "$dir" ]; then
            local c
            c=$(find "$dir" -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.webp" \) 2>/dev/null | wc -l)
            count=$((count + c))
            echo "  $dir: ${c} 枚"
        fi
    done
    echo ""
    echo "  画像合計: ${count} 枚"
}

# ------------------------------------------
# rclone が使えるか確認
# ------------------------------------------
check_rclone() {
    if ! command -v rclone &> /dev/null; then
        echo "[rclone] インストール中..."
        apt-get install -y unzip -qq 2>/dev/null
        curl -s https://rclone.org/install.sh | bash
        echo "[rclone] インストール完了"
    fi

    # rclone設定を復元
    if [ -f "$NOTEBOOKS/rclone.conf" ]; then
        mkdir -p ~/.config/rclone
        cp "$NOTEBOOKS/rclone.conf" ~/.config/rclone/rclone.conf
    fi

    if ! rclone listremotes 2>/dev/null | grep -q "^${GDRIVE_REMOTE}:"; then
        echo "エラー: rclone に '$GDRIVE_REMOTE' リモートが設定されていません"
        echo ""
        echo "設定方法:"
        echo "  1. rclone config"
        echo "  2. 'n' (new remote) -> 名前: gdrive -> タイプ: drive"
        echo "  3. 設定完了後: cp ~/.config/rclone/rclone.conf $NOTEBOOKS/rclone.conf"
        exit 1
    fi
}

# ------------------------------------------
# 同期実行
# ------------------------------------------
sync_outputs() {
    local keep_local=$1
    local synced=0
    local DEST_DIR
    DEST_DIR=$(resolve_dest_dir)

    echo "========================================"
    echo "  Google Drive に画像を転送中..."
    echo "========================================"
    echo "  日付(JST): $TODAY"
    echo "  転送先: $GDRIVE_REMOTE:$GDRIVE_BASE/$DEST_DIR/"
    if [ "$DEST_DIR" != "$TODAY" ]; then
        echo "  ※ 同日フォルダが既に存在するため $DEST_DIR に保存します"
    fi
    echo ""

    # SD WebUI インスタンス1の出力
    if [ -d "$SD_DATA_1/outputs" ] && [ "$(ls -A "$SD_DATA_1/outputs" 2>/dev/null)" ]; then
        echo "[SD #1] 転送中..."
        rclone copy "$SD_DATA_1/outputs/" "$GDRIVE_REMOTE:$GDRIVE_BASE/$DEST_DIR/sd-1/" -P
        synced=1
        if [ "$keep_local" != "true" ]; then
            find "$SD_DATA_1/outputs" -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.webp" \) -delete
            echo "[SD #1] ローカル画像を削除しました"
        fi
    else
        echo "[SD #1] 転送する画像がありません"
    fi

    # SD WebUI インスタンス2の出力
    if [ -d "$SD_DATA_2/outputs" ] && [ "$(ls -A "$SD_DATA_2/outputs" 2>/dev/null)" ]; then
        echo "[SD #2] 転送中..."
        rclone copy "$SD_DATA_2/outputs/" "$GDRIVE_REMOTE:$GDRIVE_BASE/$DEST_DIR/sd-2/" -P
        synced=1
        if [ "$keep_local" != "true" ]; then
            find "$SD_DATA_2/outputs" -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.webp" \) -delete
            echo "[SD #2] ローカル画像を削除しました"
        fi
    else
        echo "[SD #2] 転送する画像がありません"
    fi

    # ComfyUI の出力
    if [ -d "$COMFY_DIR/output" ] && [ "$(ls -A "$COMFY_DIR/output" 2>/dev/null)" ]; then
        echo "[ComfyUI] 転送中..."
        rclone copy "$COMFY_DIR/output/" "$GDRIVE_REMOTE:$GDRIVE_BASE/$DEST_DIR/comfyui/" -P
        synced=1
        if [ "$keep_local" != "true" ]; then
            find "$COMFY_DIR/output" -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.webp" \) -delete
            echo "[ComfyUI] ローカル画像を削除しました"
        fi
    else
        echo "[ComfyUI] 転送する画像がありません"
    fi

    echo ""
    if [ $synced -eq 1 ]; then
        echo "転送完了! Google Drive: $GDRIVE_REMOTE:$GDRIVE_BASE/$DEST_DIR/"
    else
        echo "転送する画像がありませんでした"
    fi
    echo ""

    # 使用量を表示
    show_status
}

# ------------------------------------------
# メイン
# ------------------------------------------
case "${1:-}" in
    --status|-s)
        show_status
        ;;
    --keep|-k)
        check_rclone
        sync_outputs true
        ;;
    --help|-h)
        echo "使い方:"
        echo "  bash sync.sh            生成画像をGDriveに転送＆ローカル削除"
        echo "  bash sync.sh --keep     転送のみ（ローカル画像を残す）"
        echo "  bash sync.sh --status   ストレージ使用量を表示"
        ;;
    "")
        check_rclone
        sync_outputs false
        ;;
    *)
        echo "不明なオプション: $1"
        echo "bash sync.sh --help で使い方を確認"
        exit 1
        ;;
esac
