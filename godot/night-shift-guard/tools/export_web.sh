#!/usr/bin/env bash
# 匯出網頁版並在本機起一個靜態伺服器預覽。
# 需要：Godot 4.7 可執行檔在 PATH（或設 GODOT 環境變數），且已安裝 export templates。
#
# 用法：
#   ./tools/export_web.sh            # 匯出 debug 版到 build/web 並起 http://localhost:8060
#   ./tools/export_web.sh release    # 匯出 release 版
#
# 單執行緒匯出不需要 COOP/COEP 標頭，任何靜態主機（GitHub Pages、itch.io）都能直接放。

set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-godot}"
MODE="${1:-debug}"
OUT="build/web"

mkdir -p "$OUT"
if [ "$MODE" = "release" ]; then
  "$GODOT" --headless --export-release "Web" "$OUT/index.html"
else
  "$GODOT" --headless --export-debug "Web" "$OUT/index.html"
fi

echo
echo "匯出完成：$OUT"
du -sh "$OUT"
echo
echo "預覽：http://localhost:8060  （Ctrl+C 結束）"
cd "$OUT" && python3 -m http.server 8060
