// 3D 視覺層：方塊島嶼 / 球體士兵 / 船 / 據點 / 特效
// 模擬座標 (sx, sy) → 世界座標 (sx - W/2, 高度, H/2 - sy)
using System.Collections.Generic;
using UnityEngine;

namespace IslandRaid {

// 建置時由 BuildScript 塞進場景，保證 Standard shader 材質進包
public class Palette : MonoBehaviour {
    public string[] names;
    public Material[] materials;
}

public class TileRef : MonoBehaviour { public int x, y; }

public static class MatLib {
    public static readonly string[] DefNames = {
        "water", "sand", "beach", "grass", "high", "rock",
        "pInfantry", "pArcher", "pPike", "enemy", "enemyVet",
        "houseBody", "flagRed", "flagBlue", "boat", "white", "gold", "night",
    };
    public static readonly Color[] DefColors = {
        C(0x2c, 0x4a, 0x7c), C(0xd8, 0xc5, 0x8f), C(0xEE, 0xE0, 0xB0), C(0x7f, 0xb0, 0x69),
        C(0x5f, 0x94, 0x52), C(0x8a, 0x8f, 0x98),
        C(0x5b, 0x9b, 0xff), C(0x4e, 0xcf, 0xae), C(0x9b, 0x8c, 0xf0),
        C(0xef, 0x7a, 0x6d), C(0xd9, 0x4f, 0x3f),
        C(0x6e, 0x46, 0x32), C(0xef, 0x7a, 0x6d), C(0x5b, 0x9b, 0xff),
        C(0x7a, 0x5a, 0x3a), Color.white, C(0xf2, 0xc5, 0x6b), C(0x14, 0x1b, 0x2b),
    };
    static Color C(int r, int g, int b) { return new Color(r / 255f, g / 255f, b / 255f); }

    static Dictionary<string, Material> map;
    public static void Init(Palette pal) {
        map = new Dictionary<string, Material>();
        if (pal != null && pal.materials != null && pal.names != null) {
            for (int i = 0; i < pal.names.Length && i < pal.materials.Length; i++)
                if (pal.materials[i] != null) map[pal.names[i]] = pal.materials[i];
        }
        // 編輯器試玩 / 備援：動態建立
        for (int i = 0; i < DefNames.Length; i++) {
            if (map.ContainsKey(DefNames[i])) continue;
            var sh = Shader.Find("Standard");
            var m = new Material(sh);
            m.color = DefColors[i];
            m.SetFloat("_Glossiness", 0f);
            map[DefNames[i]] = m;
        }
    }
    public static Material Get(string n) { return map[n]; }
    public static string SquadMat(Squad s) {
        if (s.side == Side.Enemy) return s.vet > 0 ? "enemyVet" : "enemy";
        switch (s.type) {
            case "archer": return "pArcher";
            case "pike":   return "pPike";
            default:       return "pInfantry";
        }
    }
}

public class Fx {
    public GameObject go;
    public float t, dur;
    public string type;
    public float baseY;
}

public class View {
    public const float LIFT = 0.25f;   // 每層高度
    public Camera cam;
    GameObject islandRoot, unitRoot;
    readonly Dictionary<Soldier, GameObject> soldierGos = new Dictionary<Soldier, GameObject>();
    readonly Dictionary<Arrow, GameObject> arrowGos = new Dictionary<Arrow, GameObject>();
    readonly Dictionary<Boat, GameObject> boatGos = new Dictionary<Boat, GameObject>();
    readonly Dictionary<House, GameObject> houseFlagGos = new Dictionary<House, GameObject>();
    readonly Dictionary<House, bool> houseCapShown = new Dictionary<House, bool>();
    readonly List<Fx> fxs = new List<Fx>();
    GameObject selRing, moveMarkGo;

    public static Vector3 W(float sx, float sy, float h) {
        return new Vector3(sx - Island.W * 0.5f, h, Island.H * 0.5f - sy);
    }
    public static Vector2 Sim(Vector3 world) {
        return new Vector2(world.x + Island.W * 0.5f, Island.H * 0.5f - world.z);
    }

    public void SetupScene() {
        MatLib.Init(Object.FindFirstObjectByType<Palette>());
        RenderSettings.ambientLight = new Color(0.55f, 0.6f, 0.7f);

        var camGo = Camera.main != null ? Camera.main.gameObject : new GameObject("Main Camera");
        cam = camGo.GetComponent<Camera>();
        if (cam == null) cam = camGo.AddComponent<Camera>();
        camGo.tag = "MainCamera";
        cam.orthographic = true;
        cam.orthographicSize = 9.2f;
        cam.clearFlags = CameraClearFlags.SolidColor;
        cam.backgroundColor = MatLib.DefColors[17]; // night
        camGo.transform.rotation = Quaternion.Euler(52, 0, 0);
        camGo.transform.position = new Vector3(0, 0, 0) - camGo.transform.forward * 30f
            + new Vector3(0, 0.8f, 0);

        if (Object.FindFirstObjectByType<Light>() == null) {
            var lgo = new GameObject("Sun");
            var l = lgo.AddComponent<Light>();
            l.type = LightType.Directional;
            l.intensity = 1.05f;
            l.color = new Color(1f, 0.96f, 0.88f);
            lgo.transform.rotation = Quaternion.Euler(55, -35, 0);
        }
    }

    public void BuildIsland(Island isl) {
        ClearBattle();
        if (islandRoot != null) Object.Destroy(islandRoot);
        islandRoot = new GameObject("Island");
        unitRoot = new GameObject("Units");

        // 海面（含點擊用 collider）
        var sea = GameObject.CreatePrimitive(PrimitiveType.Cube);
        sea.name = "Sea";
        sea.transform.SetParent(islandRoot.transform);
        sea.transform.position = new Vector3(0, -0.08f, 0);
        sea.transform.localScale = new Vector3(Island.W + 14, 0.1f, Island.H + 14);
        sea.GetComponent<Renderer>().material = MatLib.Get("water");

        for (int y = 0; y < Island.H; y++)
            for (int x = 0; x < Island.W; x++) {
                var t0 = isl.tiles[y, x];
                if (t0.h <= 0) continue;
                float top = t0.h * LIFT;
                const float bottom = -0.4f;
                var cube = GameObject.CreatePrimitive(PrimitiveType.Cube);
                cube.transform.SetParent(islandRoot.transform);
                float height = top - bottom;
                var wp = W(x + 0.5f, y + 0.5f, bottom + height / 2);
                cube.transform.position = wp;
                cube.transform.localScale = new Vector3(1, height, 1);
                string mat = t0.beach ? "beach" : t0.h == 1 ? "sand" : t0.h == 2 ? "grass" : t0.h == 3 ? "high" : "rock";
                cube.GetComponent<Renderer>().material = MatLib.Get(mat);
                var tr = cube.AddComponent<TileRef>();
                tr.x = x; tr.y = y;
            }

        // 據點：屋身 + 旗桿 + 旗
        foreach (var h in isl.houses) {
            float top = h.tile.h * LIFT;
            var root = new GameObject("House");
            root.transform.SetParent(islandRoot.transform);
            root.transform.position = W(h.tile.x + 0.5f, h.tile.y + 0.5f, top);

            var body = GameObject.CreatePrimitive(PrimitiveType.Cube);
            body.transform.SetParent(root.transform);
            body.transform.localPosition = new Vector3(0, 0.18f, 0);
            body.transform.localScale = new Vector3(0.55f, 0.36f, 0.45f);
            body.GetComponent<Renderer>().material = MatLib.Get("houseBody");
            Object.Destroy(body.GetComponent<Collider>());

            var pole = GameObject.CreatePrimitive(PrimitiveType.Cube);
            pole.transform.SetParent(root.transform);
            pole.transform.localPosition = new Vector3(0.28f, 0.55f, 0);
            pole.transform.localScale = new Vector3(0.05f, 0.75f, 0.05f);
            pole.GetComponent<Renderer>().material = MatLib.Get("white");
            Object.Destroy(pole.GetComponent<Collider>());

            var flag = GameObject.CreatePrimitive(PrimitiveType.Cube);
            flag.transform.SetParent(root.transform);
            flag.transform.localPosition = new Vector3(0.45f, 0.85f, 0);
            flag.transform.localScale = new Vector3(0.3f, 0.18f, 0.03f);
            flag.GetComponent<Renderer>().material = MatLib.Get("flagRed");
            Object.Destroy(flag.GetComponent<Collider>());
            houseFlagGos[h] = flag;
            houseCapShown[h] = false;
        }

        // 選取圈 / 移動標記（重複使用）
        selRing = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
        selRing.name = "SelRing";
        selRing.transform.localScale = new Vector3(0.95f, 0.02f, 0.95f);
        selRing.GetComponent<Renderer>().material = MatLib.Get("white");
        Object.Destroy(selRing.GetComponent<Collider>());
        selRing.SetActive(false);

        moveMarkGo = GameObject.CreatePrimitive(PrimitiveType.Sphere);
        moveMarkGo.name = "MoveMark";
        moveMarkGo.transform.localScale = Vector3.one * 0.18f;
        moveMarkGo.GetComponent<Renderer>().material = MatLib.Get("gold");
        Object.Destroy(moveMarkGo.GetComponent<Collider>());
        moveMarkGo.SetActive(false);
    }

    public void ClearBattle() {
        foreach (var kv in soldierGos) Object.Destroy(kv.Value);
        foreach (var kv in arrowGos) Object.Destroy(kv.Value);
        foreach (var kv in boatGos) Object.Destroy(kv.Value);
        foreach (var f in fxs) if (f.go != null) Object.Destroy(f.go);
        soldierGos.Clear(); arrowGos.Clear(); boatGos.Clear();
        houseFlagGos.Clear(); houseCapShown.Clear(); fxs.Clear();
        if (unitRoot != null) Object.Destroy(unitRoot);
        if (islandRoot != null) Object.Destroy(islandRoot);
        if (selRing != null) Object.Destroy(selRing);
        if (moveMarkGo != null) Object.Destroy(moveMarkGo);
        islandRoot = null; unitRoot = null; selRing = null; moveMarkGo = null;
    }

    float TileLift(Island isl, float sx, float sy) {
        var t0 = isl.At(sx, sy);
        return (t0 != null ? t0.h : 0) * LIFT;
    }

    public void AddFx(Battle b, string type, float sx, float sy) {
        var go = GameObject.CreatePrimitive(type == "ring" ? PrimitiveType.Cylinder : PrimitiveType.Sphere);
        Object.Destroy(go.GetComponent<Collider>());
        float lift = TileLift(b.island, sx, sy);
        string mat = type == "splash" ? "pInfantry" : type == "slash" ? "white" : type == "puff" ? "sand" : "gold";
        go.GetComponent<Renderer>().material = MatLib.Get(mat);
        float dur = type == "ring" ? 0.6f : type == "splash" ? 0.8f : 0.3f;
        go.transform.position = W(sx, sy, lift + 0.12f);
        if (type == "ring") go.transform.localScale = new Vector3(0.2f, 0.02f, 0.2f);
        else go.transform.localScale = Vector3.one * 0.12f;
        fxs.Add(new Fx { go = go, dur = dur, type = type, baseY = lift + 0.12f });
    }

    public void Sync(Battle b, Squad selected, float dt) {
        var isl = b.island;

        // 士兵
        var liveSoldiers = new HashSet<Soldier>();
        foreach (var sq in b.squads) {
            if (sq.dead || sq.onBoat) continue;
            string mat = MatLib.SquadMat(sq);
            foreach (var so in sq.soldiers) {
                liveSoldiers.Add(so);
                GameObject go;
                if (!soldierGos.TryGetValue(so, out go)) {
                    go = GameObject.CreatePrimitive(PrimitiveType.Sphere);
                    go.transform.SetParent(unitRoot.transform);
                    go.transform.localScale = Vector3.one * 0.24f;
                    Object.Destroy(go.GetComponent<Collider>());
                    go.GetComponent<Renderer>().material = MatLib.Get(mat);
                    soldierGos[so] = go;
                }
                go.transform.position = W(so.x, so.y, TileLift(isl, so.x, so.y) + 0.13f);
            }
        }
        var deadKeys = new List<Soldier>();
        foreach (var kv in soldierGos)
            if (!liveSoldiers.Contains(kv.Key)) { Object.Destroy(kv.Value); deadKeys.Add(kv.Key); }
        foreach (var k in deadKeys) soldierGos.Remove(k);

        // 船
        foreach (var bt in b.boats) {
            GameObject go;
            if (!boatGos.TryGetValue(bt, out go)) {
                go = new GameObject("Boat");
                go.transform.SetParent(unitRoot.transform);
                var hull = GameObject.CreatePrimitive(PrimitiveType.Cube);
                hull.transform.SetParent(go.transform);
                hull.transform.localScale = new Vector3(0.9f, 0.16f, 0.42f);
                hull.GetComponent<Renderer>().material = MatLib.Get("boat");
                Object.Destroy(hull.GetComponent<Collider>());
                var mast = GameObject.CreatePrimitive(PrimitiveType.Cube);
                mast.transform.SetParent(go.transform);
                mast.transform.localPosition = new Vector3(0, 0.35f, 0);
                mast.transform.localScale = new Vector3(0.05f, 0.6f, 0.05f);
                mast.GetComponent<Renderer>().material = MatLib.Get("white");
                Object.Destroy(mast.GetComponent<Collider>());
                var sail = GameObject.CreatePrimitive(PrimitiveType.Cube);
                sail.transform.SetParent(go.transform);
                sail.transform.localPosition = new Vector3(0.15f, 0.5f, 0);
                sail.transform.localScale = new Vector3(0.28f, 0.2f, 0.03f);
                sail.GetComponent<Renderer>().material = MatLib.Get(MatLib.SquadMat(bt.squad));
                Object.Destroy(sail.GetComponent<Collider>());
                boatGos[bt] = go;
            }
            go.SetActive(bt.state != "landed");
            if (bt.state != "landed")
                go.transform.position = W(bt.x, bt.y, 0.05f + Mathf.Sin(bt.bob) * 0.03f);
        }

        // 箭矢（拋物線）
        var liveArrows = new HashSet<Arrow>();
        foreach (var a in b.arrows) {
            liveArrows.Add(a);
            GameObject go;
            if (!arrowGos.TryGetValue(a, out go)) {
                go = GameObject.CreatePrimitive(PrimitiveType.Cube);
                go.transform.SetParent(unitRoot.transform);
                go.transform.localScale = new Vector3(0.04f, 0.04f, 0.3f);
                Object.Destroy(go.GetComponent<Collider>());
                go.GetComponent<Renderer>().material =
                    MatLib.Get(a.side == Side.Player ? "white" : "gold");
                arrowGos[a] = go;
            }
            float k = Mathf.Clamp01(a.t / a.dur);
            float sx = a.sx + (a.tx - a.sx) * k, sy = a.sy + (a.ty - a.sy) * k;
            float arc = Mathf.Sin(k * Mathf.PI) * 0.9f;
            var p0 = go.transform.position;
            var p1 = W(sx, sy, TileLift(isl, sx, sy) + 0.25f + arc);
            go.transform.position = p1;
            if ((p1 - p0).sqrMagnitude > 1e-6f) go.transform.rotation = Quaternion.LookRotation(p1 - p0);
        }
        var goneArrows = new List<Arrow>();
        foreach (var kv in arrowGos)
            if (!liveArrows.Contains(kv.Key)) { Object.Destroy(kv.Value); goneArrows.Add(kv.Key); }
        foreach (var k in goneArrows) arrowGos.Remove(k);

        // 據點旗幟
        foreach (var h in isl.houses) {
            if (h.captured && houseFlagGos.ContainsKey(h) && !houseCapShown[h]) {
                houseCapShown[h] = true;
                houseFlagGos[h].GetComponent<Renderer>().material = MatLib.Get("flagBlue");
            }
        }

        // 選取圈
        if (selected != null && !selected.dead) {
            selRing.SetActive(true);
            float lift = selected.onBoat ? 0.08f : TileLift(isl, selected.x, selected.y);
            selRing.transform.position = W(selected.x, selected.y, lift + 0.03f);
            float pulse = 0.95f + Mathf.Sin(b.time * 5f) * 0.06f;
            selRing.transform.localScale = new Vector3(pulse, 0.02f, pulse);
        } else selRing.SetActive(false);

        // 移動標記
        if (selected != null && !selected.dead && selected.moveMarkT < 1.2f) {
            moveMarkGo.SetActive(true);
            var m = selected.moveMark;
            var t0 = isl.Get(m.x, m.y);
            float lift = (t0 != null ? t0.h : 0) * LIFT;
            moveMarkGo.transform.position = W(m.x + 0.5f, m.y + 0.5f,
                lift + 0.25f + Mathf.Sin(b.time * 6f) * 0.06f);
        } else moveMarkGo.SetActive(false);

        // 特效
        for (int i = fxs.Count - 1; i >= 0; i--) {
            var f = fxs[i];
            f.t += dt;
            float k = Mathf.Clamp01(f.t / f.dur);
            if (f.t >= f.dur) {
                if (f.go != null) Object.Destroy(f.go);
                fxs.RemoveAt(i);
                continue;
            }
            if (f.type == "ring") {
                float r = 0.2f + k * 1.6f;
                f.go.transform.localScale = new Vector3(r, 0.02f, r);
            } else if (f.type == "splash") {
                f.go.transform.localScale = Vector3.one * (0.1f + k * 0.35f);
                var p = f.go.transform.position;
                f.go.transform.position = new Vector3(p.x, f.baseY + k * 0.4f * (1 - k) * 4f * 0.3f, p.z);
            } else {
                f.go.transform.localScale = Vector3.one * (0.1f + k * 0.15f);
            }
        }
    }
}

}
