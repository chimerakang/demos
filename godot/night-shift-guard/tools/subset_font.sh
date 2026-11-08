#!/usr/bin/env bash
# 產生中文字型子集，只保留遊戲文本實際用到的字，讓網頁版不用載十幾 MB 的字型。
#
# 用法：
#   1. 下載 Noto Sans TC（https://fonts.google.com/noto/specimen/Noto+Sans+TC），
#      把 NotoSansTC-Regular.ttf 放到 assets/fonts/
#   2. pip install fonttools brotli
#   3. ./tools/subset_font.sh
#   4. 到 project.godot 取消 gui/theme/custom_font 那行註解
#
# 每次新增大量文本後重跑一次即可。

set -euo pipefail
cd "$(dirname "$0")/.."

SRC="assets/fonts/NotoSansTC-Regular.ttf"
OUT="assets/fonts/NotoSansTC-subset.ttf"
CHARS_FILE="build/used_chars.txt"

if [ ! -f "$SRC" ]; then
  echo "找不到 $SRC，請先下載 Noto Sans TC" >&2
  exit 1
fi

mkdir -p build

# 收集所有 JSON、GDScript、場景檔裡出現的字元，加上常用標點與數字字母
python3 - <<'PY' > "$CHARS_FILE"
import glob, io
chars = set()
for pattern in ("data/**/*.json", "scripts/**/*.gd", "scenes/**/*.gd", "scenes/**/*.tscn"):
    for path in glob.glob(pattern, recursive=True):
        with io.open(path, encoding="utf-8") as f:
            chars.update(f.read())
# 基本 ASCII + 全形標點 + 常用符號
chars.update(chr(c) for c in range(0x20, 0x7F))
chars.update("，。、；：？！「」『』（）《》〈〉—…·～％＋－×÷＝→↔✓✗☎📄•")
print("".join(sorted(c for c in chars if not c.isspace() or c == " ")), end="")
PY

echo "使用字元數：$(python3 -c "import io;print(len(io.open('$CHARS_FILE',encoding='utf-8').read()))")"

pyftsubset "$SRC" \
  --text-file="$CHARS_FILE" \
  --output-file="$OUT" \
  --layout-features='*' \
  --no-hinting \
  --desubroutinize

ls -lh "$OUT"
echo "完成。請在 project.godot 啟用 gui/theme/custom_font=\"res://$OUT\""
