#!/bin/bash

# ============================================
#  Paperspace SD Launcher
# ============================================
# 使い方:
#   bash start.sh              → メニュー表示
#   bash start.sh sd           → SD WebUI のみ
#   bash start.sh comfy        → ComfyUI のみ
#   bash start.sh sd comfy     → SD WebUI + ComfyUI
#   bash start.sh sd sd        → SD WebUI × 2
#   bash start.sh sd sd comfy  → SD WebUI × 2 + ComfyUI
#
# Paperspace ディレクトリ構成:
#   /notebooks/  → ノートブック専用の永続ストレージ (50GB制限)
#   /storage/    → チーム共有の永続ストレージ
#   /tmp/        → 一時領域 (セッション終了で消える)

NOTEBOOKS="/notebooks"
SD_DIR="$NOTEBOOKS/stable-diffusion-webui"
COMFY_DIR="$NOTEBOOKS/ComfyUI"
SD_DATA_1="$NOTEBOOKS/sd-data-1"
SD_DATA_2="$NOTEBOOKS/sd-data-2"
LOG_DIR="$NOTEBOOKS/logs"

SD_PORT_1=7860
SD_PORT_2=7861
COMFY_PORT=8188

mkdir -p "$LOG_DIR"

# ------------------------------------------
# rclone 設定の復元
# ------------------------------------------
restore_rclone() {
    if [ -f "$NOTEBOOKS/rclone.conf" ]; then
        mkdir -p ~/.config/rclone
        cp "$NOTEBOOKS/rclone.conf" ~/.config/rclone/rclone.conf
        echo "[rclone] 設定を復元しました"
    fi
}

# ------------------------------------------
# SD WebUI 起動関数
# ------------------------------------------
start_sd() {
    local instance=$1  # 1 or 2
    local port data_dir log_file

    if [ "$instance" = "2" ]; then
        port=$SD_PORT_2
        data_dir=$SD_DATA_2
        log_file="$LOG_DIR/sd-2.log"
    else
        port=$SD_PORT_1
        data_dir=$SD_DATA_1
        log_file="$LOG_DIR/sd-1.log"
    fi

    # Stability AI の元リポジトリが非公開のため、フォーク版を指定
    export STABLE_DIFFUSION_REPO="https://github.com/Kantyadoram/stable-diffusion-stability-ai.git"
    export STABLE_DIFFUSION_COMMIT_HASH="7435a5be1050962a936a4ef624b43814ee8824a8"

    echo "[SD WebUI #$instance] 起動中... (port: $port)"
    cd "$SD_DIR"
    python launch.py \
        --listen \
        --port "$port" \
        --share \
        --data-dir "$data_dir" \
        --enable-insecure-extension-access \
        --xformers \
        > "$log_file" 2>&1 &

    echo "[SD WebUI #$instance] PID: $! | ログ: $log_file"
}

# ------------------------------------------
# ComfyUI 起動関数
# ------------------------------------------
start_comfy() {
    local log_file="$LOG_DIR/comfy.log"

    echo "[ComfyUI] 起動中... (port: $COMFY_PORT)"
    cd "$COMFY_DIR"
    python main.py \
        --listen 0.0.0.0 \
        --port "$COMFY_PORT" \
        > "$log_file" 2>&1 &

    echo "[ComfyUI] PID: $! | ログ: $log_file"
}

# ------------------------------------------
# share リンクの取得・表示
# ------------------------------------------
wait_for_links() {
    echo ""
    echo "起動を待っています... (最大3分)"
    echo "----------------------------------------"

    local waited=0
    local max_wait=180
    local found_links=""

    while [ $waited -lt $max_wait ]; do
        sleep 5
        waited=$((waited + 5))

        # SD WebUI の gradio.live リンクを検出
        for log in "$LOG_DIR"/sd-*.log; do
            [ -f "$log" ] || continue
            local name
            name=$(basename "$log" .log)
            # 既に表示済みならスキップ
            echo "$found_links" | grep -q "$name" && continue
            if grep -q "gradio.live" "$log" 2>/dev/null; then
                local link
                link=$(grep -o "https://[a-z0-9]*.gradio.live" "$log" | head -1)
                if [ -n "$link" ]; then
                    echo "  $name: $link"
                    found_links="$found_links $name"
                fi
            fi
            # エラー検出
            if grep -q "Error" "$log" 2>/dev/null && [ $waited -ge 30 ]; then
                echo "  $name: 起動エラーの可能性あり -> tail -50 $log で確認"
            fi
        done

        # ComfyUI の起動検出
        if [ -f "$LOG_DIR/comfy.log" ]; then
            if ! echo "$found_links" | grep -q "comfy"; then
                if grep -q "To see the GUI" "$LOG_DIR/comfy.log" 2>/dev/null; then
                    echo "  comfy: http://localhost:$COMFY_PORT (ノートブック内からアクセス)"
                    found_links="$found_links comfy"
                fi
            fi
        fi

        # 全サービスが起動したか確認
        local all_ready=true
        for log in "$LOG_DIR"/sd-*.log; do
            [ -f "$log" ] || continue
            if ! grep -q "gradio.live\|Running on" "$log" 2>/dev/null; then
                all_ready=false
            fi
        done
        if [ -f "$LOG_DIR/comfy.log" ] && ! grep -q "To see the GUI" "$LOG_DIR/comfy.log" 2>/dev/null; then
            all_ready=false
        fi

        if $all_ready && [ $waited -ge 10 ]; then
            break
        fi
    done

    echo "----------------------------------------"
    echo ""
    echo "セッション終了前: bash sync.sh で画像をGDriveに転送"
    echo "ログ確認:         tail -f $LOG_DIR/sd-1.log"
    echo "ストレージ確認:   bash sync.sh --status"
    echo "全停止:           kill \$(jobs -p) 2>/dev/null"
}

# ------------------------------------------
# メニュー表示
# ------------------------------------------
show_menu() {
    echo "========================================"
    echo "  Paperspace SD Launcher"
    echo "========================================"
    echo ""
    echo "  1) SD WebUI のみ"
    echo "  2) ComfyUI のみ"
    echo "  3) SD WebUI + ComfyUI"
    echo "  4) SD WebUI x 2"
    echo "  5) SD WebUI x 2 + ComfyUI"
    echo ""
    read -r -p "選択 [1-5]: " choice

    case $choice in
        1) LAUNCH_SD1=true ;;
        2) LAUNCH_COMFY=true ;;
        3) LAUNCH_SD1=true; LAUNCH_COMFY=true ;;
        4) LAUNCH_SD1=true; LAUNCH_SD2=true ;;
        5) LAUNCH_SD1=true; LAUNCH_SD2=true; LAUNCH_COMFY=true ;;
        *)
            echo "無効な選択です"
            exit 1
            ;;
    esac
}

# ------------------------------------------
# 引数パース
# ------------------------------------------
LAUNCH_SD1=false
LAUNCH_SD2=false
LAUNCH_COMFY=false

if [ $# -eq 0 ]; then
    show_menu
else
    sd_count=0
    for arg in "$@"; do
        case $arg in
            sd|SD)
                sd_count=$((sd_count + 1))
                if [ $sd_count -eq 1 ]; then
                    LAUNCH_SD1=true
                else
                    LAUNCH_SD2=true
                fi
                ;;
            comfy|COMFY|comfyui|ComfyUI)
                LAUNCH_COMFY=true
                ;;
            *)
                echo "不明な引数: $arg (sd / comfy を指定してください)"
                exit 1
                ;;
        esac
    done
fi

# ------------------------------------------
# メイン処理
# ------------------------------------------
echo ""

# 既存の SD WebUI / ComfyUI プロセスを停止
existing_pids=$(ps aux | grep -E "launch\.py|main\.py" | grep -v grep | awk '{print $2}')
if [ -n "$existing_pids" ]; then
    echo "既存プロセスを停止中..."
    echo "$existing_pids" | xargs kill 2>/dev/null
    sleep 2
fi

# 古いログを削除
rm -f "$LOG_DIR"/sd-*.log "$LOG_DIR"/comfy.log

# rclone 復元
restore_rclone

# 起動
if $LAUNCH_SD1; then
    start_sd 1
fi

if $LAUNCH_SD2; then
    start_sd 2
fi

if $LAUNCH_COMFY; then
    start_comfy
fi

# リンク表示を待つ
wait_for_links
