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
MODELS_DIR="$NOTEBOOKS/models"
SD_DIR="$NOTEBOOKS/stable-diffusion-webui"
COMFY_DIR="$NOTEBOOKS/ComfyUI"
COMFY_VENV="$NOTEBOOKS/comfy-venv"
SD_DATA_1="$NOTEBOOKS/sd-data-1"
SD_DATA_2="$NOTEBOOKS/sd-data-2"
LOG_DIR="$NOTEBOOKS/logs"

SD_PORT_1=7860
SD_PORT_2=7861
COMFY_PORT=8188

# Python の出力バッファリングを無効化 (ログがリアルタイムで書き込まれるようにする)
export PYTHONUNBUFFERED=1

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
# ControlNet 依存パッケージの修復
# ------------------------------------------
fix_controlnet_deps() {
    local aux_init="/usr/local/lib/python3.11/dist-packages/controlnet_aux/__init__.py"

    # controlnet_aux が未インストール or パッチ未適用の場合のみ実行
    if [ ! -f "$aux_init" ] || ! grep -q "mediapipe_face disabled" "$aux_init" 2>/dev/null; then
        echo "[ControlNet] 依存パッケージを修復中..."
        pip install controlnet_aux==0.0.10 -q 2>/dev/null
        # mediapipe_face の非互換インポートを無効化 (mediapipe API変更による)
        sed -i 's/from \.mediapipe_face import MediapipeFaceDetector/pass  # mediapipe_face disabled/' "$aux_init" 2>/dev/null
        echo "[ControlNet] 修復完了"
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
        --ckpt-dir "$MODELS_DIR/checkpoints" \
        --lora-dir "$MODELS_DIR/loras" \
        --vae-dir "$MODELS_DIR/vae" \
        --embeddings-dir "$MODELS_DIR/embeddings" \
        --enable-insecure-extension-access \
        --xformers \
        --no-download-sd-model \
        > "$log_file" 2>&1 &

    echo "[SD WebUI #$instance] PID: $! | ログ: $log_file"
}

# ------------------------------------------
# ComfyUI 仮想環境の準備
# ------------------------------------------
fix_comfy_deps() {
    if [ ! -d "$COMFY_DIR" ]; then
        return
    fi

    # venv が未作成の場合は作成 (システムパッケージと完全に隔離)
    if [ ! -d "$COMFY_VENV" ]; then
        echo "[ComfyUI] 仮想環境を作成中..."
        python -m venv "$COMFY_VENV"
    fi

    # torch が未インストール or バージョン不足の場合はインストール
    if ! "$COMFY_VENV/bin/python" -c "import torch; assert hasattr(torch, 'uint64')" 2>/dev/null; then
        echo "[ComfyUI] PyTorch (CUDA 12.1) をインストール中..."
        "$COMFY_VENV/bin/pip" install torch torchvision torchaudio \
            --index-url https://download.pytorch.org/whl/cu121 -q 2>/dev/null
        echo "[ComfyUI] PyTorch インストール完了"
    fi

    # ComfyUI の依存パッケージをインストール
    if ! "$COMFY_VENV/bin/python" -c "import alembic" 2>/dev/null; then
        echo "[ComfyUI] 依存パッケージをインストール中..."
        "$COMFY_VENV/bin/pip" install -r "$COMFY_DIR/requirements.txt" -q 2>/dev/null
        echo "[ComfyUI] インストール完了"
    fi
}

# ------------------------------------------
# ComfyUI 起動関数
# ------------------------------------------
start_comfy() {
    local log_file="$LOG_DIR/comfy.log"

    echo "[ComfyUI] 起動中... (port: $COMFY_PORT, venv)"
    cd "$COMFY_DIR"
    "$COMFY_VENV/bin/python" main.py \
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
            # 致命的エラー検出 (スクリプト読み込みエラーは無視)
            if grep -q "RuntimeError\|CUDA Setup failed\|Torch is not able to use GPU" "$log" 2>/dev/null && [ $waited -ge 30 ]; then
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
            if ! grep -q "gradio.live" "$log" 2>/dev/null; then
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

# ControlNet 依存パッケージの修復
fix_controlnet_deps

# ComfyUI 依存パッケージのインストール
if $LAUNCH_COMFY; then
    fix_comfy_deps
fi

# 起動
if $LAUNCH_SD1; then
    start_sd 1
fi

if $LAUNCH_SD2; then
    if $LAUNCH_SD1; then
        # SD #1 の share リンク確立まで待機 (pip 競合 + ネットワーク競合回避)
        echo "[SD WebUI #2] SD #1 の起動完了を待機中..."
        waited=0
        while [ $waited -lt 300 ]; do
            sleep 5
            waited=$((waited + 5))
            if grep -q "gradio.live\|Could not create share link\|Startup time" "$LOG_DIR/sd-1.log" 2>/dev/null; then
                echo "[SD WebUI #2] SD #1 起動完了、SD #2 を起動します"
                break
            fi
        done
    fi
    start_sd 2
fi

if $LAUNCH_COMFY; then
    start_comfy
fi

# リンク表示を待つ
wait_for_links
