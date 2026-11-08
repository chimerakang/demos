#!/usr/bin/env python3
"""
只下載 Godot export templates 裡的網頁模板（約 20–40 MB），
不用抓整包 1 GB 的 .tpz。靠 HTTP Range 讀遠端 zip 的目錄表再抽單一檔案。

用法：
    python3 tools/fetch_web_templates.py [4.7-stable] [~/.local/share/godot/export_templates]

裝好之後 `godot --headless --export-release "Web" ...` 就能用（單執行緒模板）。
"""
import io
import os
import struct
import sys
import zipfile
import zlib
from pathlib import Path
from urllib.request import Request, urlopen

VERSION = sys.argv[1] if len(sys.argv) > 1 else "4.7-stable"
DEST_ROOT = Path(sys.argv[2]).expanduser() if len(sys.argv) > 2 else Path.home() / ".local/share/godot/export_templates"
URL = f"https://github.com/godotengine/godot-builds/releases/download/{VERSION}/Godot_v{VERSION}_export_templates.tpz"
WANTED = ["templates/web_nothreads_release.zip", "templates/web_nothreads_debug.zip", "templates/version.txt"]


def ranged_get(url: str, start: int, end: int) -> bytes:
    req = Request(url, headers={"Range": f"bytes={start}-{end}", "User-Agent": "godot-web-template-fetcher"})
    with urlopen(req, timeout=120) as r:
        if r.status not in (200, 206):
            raise RuntimeError(f"HTTP {r.status}")
        return r.read()


def total_size(url: str) -> int:
    req = Request(url, headers={"Range": "bytes=0-0", "User-Agent": "godot-web-template-fetcher"})
    with urlopen(req, timeout=120) as r:
        cr = r.headers.get("Content-Range", "")
        if "/" in cr:
            return int(cr.rsplit("/", 1)[1])
        cl = r.headers.get("Content-Length")
        if cl:
            return int(cl)
    raise RuntimeError("無法取得檔案大小")


class RangedFile(io.RawIOBase):
    """給 zipfile 用的遠端檔案；只用明確的 bytes=start-end，不用後綴 range。"""

    def __init__(self, url: str, size: int, block: int = 1 << 20):
        self.url, self.size, self.block = url, size, block
        self.pos = 0
        self.cache: dict[int, bytes] = {}

    def seekable(self): return True
    def readable(self): return True
    def tell(self): return self.pos

    def seek(self, offset, whence=io.SEEK_SET):
        if whence == io.SEEK_SET: self.pos = offset
        elif whence == io.SEEK_CUR: self.pos += offset
        else: self.pos = self.size + offset
        return self.pos

    def _block(self, idx: int) -> bytes:
        if idx not in self.cache:
            start = idx * self.block
            end = min(start + self.block, self.size) - 1
            self.cache[idx] = ranged_get(self.url, start, end)
        return self.cache[idx]

    def read(self, n=-1):
        if n < 0 or self.pos + n > self.size:
            n = self.size - self.pos
        out = bytearray()
        while n > 0:
            idx, off = divmod(self.pos, self.block)
            chunk = self._block(idx)[off:off + n]
            out += chunk
            self.pos += len(chunk)
            n -= len(chunk)
        return bytes(out)


def main() -> None:
    print(f"來源：{URL}")
    # 先解析重導向後的實際網址，避免每個 range 都跑一次 302
    req = Request(URL, headers={"Range": "bytes=0-0", "User-Agent": "godot-web-template-fetcher"})
    with urlopen(req, timeout=120) as r:
        real_url = r.geturl()
    size = total_size(real_url)
    print(f"總大小：{size / 1048576:.0f} MB（只會抓需要的部分）")

    rf = RangedFile(real_url, size)
    with zipfile.ZipFile(rf) as z:
        version_txt = z.read("templates/version.txt").decode().strip()
        print(f"模板版本：{version_txt}")
        dest = DEST_ROOT / version_txt
        dest.mkdir(parents=True, exist_ok=True)
        for name in WANTED:
            info = z.getinfo(name)
            target = dest / Path(name).name
            print(f"  抽出 {name} ({info.file_size / 1048576:.1f} MB) → {target}")
            with z.open(info) as src, open(target, "wb") as dst:
                while True:
                    buf = src.read(1 << 20)
                    if not buf:
                        break
                    dst.write(buf)
    print("完成。")


if __name__ == "__main__":
    main()
