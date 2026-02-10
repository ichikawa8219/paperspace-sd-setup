#!/bin/bash

# ============================================
#  Keepalive - Paperspace 非アクティブシャットダウン対策
# ============================================
# 10分間隔でログを確認し、ターミナルに出力することで
# Paperspace の非アクティブ検出を回避する
#
# 使い方: 別ターミナルで実行
#   bash keepalive.sh
#
# 停止: Ctrl+C

LOG_DIR="/notebooks/logs"
INTERVAL=600  # 10分

echo "========================================"
echo "  Keepalive - 非アクティブシャットダウン対策"
echo "========================================"
echo ""
echo "  間隔: ${INTERVAL}秒 (10分)"
echo "  停止: Ctrl+C"
echo ""
echo "----------------------------------------"

while true; do
    sleep $INTERVAL

    ts=$(date "+%H:%M:%S")
    status=""

    for log in "$LOG_DIR"/sd-*.log "$LOG_DIR"/comfy.log; do
        [ -f "$log" ] || continue
        name=$(basename "$log" .log)
        lines=$(wc -l < "$log")
        status="$status $name:${lines}L"
    done

    # プロセス生存チェック
    procs=$(ps aux | grep -cE "launch\.py|main\.py" | grep -v grep)
    procs=$((procs - 0))  # 数値に変換

    echo "[keepalive $ts] procs:$procs$status"
done
