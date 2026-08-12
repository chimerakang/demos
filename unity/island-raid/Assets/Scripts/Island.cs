// 島嶼產生（值雜訊 + 放射衰減 + 高度平滑）與 BFS 尋路
using System;
using System.Collections.Generic;
using UnityEngine;

namespace IslandRaid {

public class Tile {
    public int x, y, h;          // h: 0 海 / 1 低地 / 2 平原 / 3 高地 / 4 岩峰
    public bool ocean, beach;
    public int house = -1;
    public float shade;
}

public class House {
    public Tile tile;
    public bool captured;
    public float progress;
}

public class Island {
    public const int W = 22, H = 22;
    public Tile[,] tiles;
    public List<Tile> beaches;
    public List<House> houses;
    public int diff;

    public Tile Get(int x, int y) {
        return (x >= 0 && y >= 0 && x < W && y < H) ? tiles[y, x] : null;
    }
    // 模擬座標（格單位，格中心 = x+0.5）
    public Tile At(float px, float py) {
        return Get((int)Mathf.Floor(px), (int)Mathf.Floor(py));
    }
}

public static class IslandGen {
    static readonly int[,] DIR = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } };

    public static Island Generate(int diff, uint seed) {
        int W = Island.W, H = Island.H;
        var ir = new Rng(seed);

        // 值雜訊
        const int gsz = 6;
        var g = new float[gsz + 1, gsz + 1];
        for (int y = 0; y <= gsz; y++)
            for (int x = 0; x <= gsz; x++) g[y, x] = ir.Next();
        Func<float, float> sm = t => t * t * (3 - 2 * t);
        Func<float, float, float> noise = (fx, fy) => {
            float gx = fx * gsz, gy = fy * gsz;
            int x0 = Mathf.Clamp((int)gx, 0, gsz - 1), y0 = Mathf.Clamp((int)gy, 0, gsz - 1);
            float sx = gx - x0, sy = gy - y0;
            float a = g[y0, x0], b = g[y0, x0 + 1], c = g[y0 + 1, x0], d = g[y0 + 1, x0 + 1];
            return a + (b - a) * sm(sx) + (c - a) * sm(sy) + (a - b - c + d) * sm(sx) * sm(sy);
        };

        var tiles = new Tile[H, W];
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++) {
                float nx = (x + 0.5f) / W - 0.5f, ny = (y + 0.5f) / H - 0.5f;
                float rad = Mathf.Sqrt(nx * nx + ny * ny) * 2f;
                float e = noise((float)x / W, (float)y / H) * 1.15f - rad * 1.05f + 0.42f;
                int h = e < 0 ? 0 : e < 0.14f ? 1 : e < 0.3f ? 2 : e < 0.44f ? 3 : 4;
                if (x == 0 || y == 0 || x == W - 1 || y == H - 1) h = 0;
                tiles[y, x] = new Tile { x = x, y = y, h = h, shade = ir.Range(-1f, 1f) };
            }

        // 只留最大陸塊
        var seen = new HashSet<int>();
        List<Vector2Int> best = null;
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++) {
                if (tiles[y, x].h == 0 || seen.Contains(y * W + x)) continue;
                var comp = new List<Vector2Int>();
                var st = new Stack<Vector2Int>();
                st.Push(new Vector2Int(x, y)); seen.Add(y * W + x);
                while (st.Count > 0) {
                    var c = st.Pop(); comp.Add(c);
                    for (int i = 0; i < 4; i++) {
                        int nx2 = c.x + DIR[i, 0], ny2 = c.y + DIR[i, 1];
                        if (nx2 < 0 || ny2 < 0 || nx2 >= W || ny2 >= H) continue;
                        int k = ny2 * W + nx2;
                        if (tiles[ny2, nx2].h > 0 && !seen.Contains(k)) { seen.Add(k); st.Push(new Vector2Int(nx2, ny2)); }
                    }
                }
                if (best == null || comp.Count > best.Count) best = comp;
            }
        var bestSet = new HashSet<int>();
        if (best != null) foreach (var c in best) bestSet.Add(c.y * W + c.x);
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++)
                if (tiles[y, x].h > 0 && !bestSet.Contains(y * W + x)) tiles[y, x].h = 0;

        // 高度平滑：相鄰落差 ≤1，保證可通行
        bool changed = true;
        while (changed) {
            changed = false;
            for (int y = 0; y < H; y++)
                for (int x = 0; x < W; x++) {
                    var t0 = tiles[y, x];
                    if (t0.h <= 1) continue;
                    int lo = 99;
                    for (int i = 0; i < 4; i++) {
                        int nx2 = x + DIR[i, 0], ny2 = y + DIR[i, 1];
                        if (nx2 < 0 || ny2 < 0 || nx2 >= W || ny2 >= H) continue;
                        var n = tiles[ny2, nx2];
                        if (n.h > 0) lo = Mathf.Min(lo, n.h);
                    }
                    if (lo < 99 && t0.h > lo + 1) { t0.h = lo + 1; changed = true; }
                }
        }

        // 海洋（連通邊界的水域）；內陸積水填為低地
        var ocean = new HashSet<int>();
        var q = new Queue<Vector2Int>();
        q.Enqueue(new Vector2Int(0, 0)); ocean.Add(0);
        while (q.Count > 0) {
            var c = q.Dequeue();
            for (int i = 0; i < 4; i++) {
                int nx2 = c.x + DIR[i, 0], ny2 = c.y + DIR[i, 1];
                if (nx2 < 0 || ny2 < 0 || nx2 >= W || ny2 >= H) continue;
                int k = ny2 * W + nx2;
                if (tiles[ny2, nx2].h == 0 && !ocean.Contains(k)) { ocean.Add(k); q.Enqueue(new Vector2Int(nx2, ny2)); }
            }
        }
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++) {
                var t0 = tiles[y, x];
                t0.ocean = t0.h == 0 && ocean.Contains(y * W + x);
                if (t0.h == 0 && !t0.ocean) t0.h = 1;
            }

        // 灘頭：h==1 且鄰海
        var beaches = new List<Tile>();
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++) {
                var t0 = tiles[y, x];
                if (t0.h != 1) continue;
                for (int i = 0; i < 4; i++) {
                    int nx2 = x + DIR[i, 0], ny2 = y + DIR[i, 1];
                    if (nx2 < 0 || ny2 < 0 || nx2 >= W || ny2 >= H) continue;
                    if (tiles[ny2, nx2].ocean) { t0.beach = true; break; }
                }
                if (t0.beach) beaches.Add(t0);
            }

        // 據點：最遠點取樣
        int nHouses = 3 + Mathf.Min(2, diff >> 1);
        var cand = new List<Tile>();
        for (int y = 2; y < H - 2; y++)
            for (int x = 2; x < W - 2; x++)
                if (tiles[y, x].h >= 2) cand.Add(tiles[y, x]);
        var housesT = new List<Tile>();
        if (cand.Count > 0) {
            housesT.Add(cand[Mathf.Clamp((int)(ir.Next() * cand.Count), 0, cand.Count - 1)]);
            while (housesT.Count < nHouses) {
                Tile far = null; float fd = -1;
                foreach (var c in cand) {
                    float d = float.MaxValue;
                    foreach (var hh in housesT)
                        d = Mathf.Min(d, Vector2.Distance(new Vector2(c.x, c.y), new Vector2(hh.x, hh.y)));
                    if (d > fd) { fd = d; far = c; }
                }
                if (fd < 3 || far == null) break;
                housesT.Add(far);
            }
        }
        var houses = new List<House>();
        for (int i = 0; i < housesT.Count; i++) {
            housesT[i].house = i;
            houses.Add(new House { tile = housesT[i] });
        }

        return new Island { tiles = tiles, beaches = beaches, houses = houses, diff = diff };
    }

    // BFS 尋路：land 模式限制相鄰落差 ≤1；water 模式只走海面
    public static List<Vector2Int> FindPath(Island isl, int sx, int sy, int tx, int ty, bool water) {
        int W = Island.W, H = Island.H;
        Func<Tile, bool> pass = water ? (Func<Tile, bool>)(t => t.ocean) : (Func<Tile, bool>)(t => t.h > 0);
        var start = isl.Get(sx, sy);
        var goal = isl.Get(tx, ty);
        if (start == null || goal == null || !pass(goal)) return null;
        var prev = new Dictionary<int, int>();
        var q = new Queue<Vector2Int>();
        q.Enqueue(new Vector2Int(sx, sy));
        prev[sy * W + sx] = -1;
        while (q.Count > 0) {
            var c = q.Dequeue();
            if (c.x == tx && c.y == ty) {
                var path = new List<Vector2Int>();
                var cur = new Vector2Int(tx, ty);
                while (true) {
                    path.Insert(0, cur);
                    int p = prev[cur.y * W + cur.x];
                    if (p < 0) break;
                    cur = new Vector2Int(p % W, p / W);
                }
                path.RemoveAt(0); // 移除起點
                return path;
            }
            for (int i = 0; i < 4; i++) {
                int nx = c.x + DIR[i, 0], ny = c.y + DIR[i, 1];
                if (nx < 0 || ny < 0 || nx >= W || ny >= H || prev.ContainsKey(ny * W + nx)) continue;
                var a = isl.tiles[c.y, c.x];
                var b = isl.tiles[ny, nx];
                if (!pass(b)) continue;
                if (!water && !(a.h > 0 && b.h > 0 && Mathf.Abs(a.h - b.h) <= 1)) continue;
                prev[ny * W + nx] = c.y * W + c.x;
                q.Enqueue(new Vector2Int(nx, ny));
            }
        }
        return null;
    }

    public static Tile NearestReachable(Island isl, int tx, int ty) {
        Tile bestT = null; float bd = float.MaxValue;
        for (int y = Mathf.Max(0, ty - 2); y <= Mathf.Min(Island.H - 1, ty + 2); y++)
            for (int x = Mathf.Max(0, tx - 2); x <= Mathf.Min(Island.W - 1, tx + 2); x++) {
                if (isl.tiles[y, x].h <= 0) continue;
                float d = Vector2.Distance(new Vector2(x, y), new Vector2(tx, ty));
                if (d < bd) { bd = d; bestT = isl.tiles[y, x]; }
            }
        return bestT;
    }
}

}
