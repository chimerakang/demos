// 奪島遠征 Island Raid v2 (Unity port)
// 核心資料：RNG / 兵種 / 技能 / 戰役狀態
using System.Collections.Generic;
using UnityEngine;

namespace IslandRaid {

// mulberry32 — 與 JS 原型同款，同種子同戰役
public class Rng {
    uint s;
    public Rng(uint seed) { s = seed; }
    public float Next() {
        unchecked {
            s += 0x6D2B79F5u;
            uint t = s;
            t = (t ^ (t >> 15)) * (t | 1u);
            t ^= t + (t ^ (t >> 7)) * (t | 61u);
            uint r = t ^ (t >> 14);
            return r / 4294967296f;
        }
    }
    public float Range(float a, float b) { return a + Next() * (b - a); }
    public int RangeInt(int a, int bIncl) {
        int v = a + (int)(Next() * (bIncl - a + 1));
        return Mathf.Clamp(v, a, bIncl);
    }
    public T Pick<T>(IList<T> list) {
        return list[Mathf.Clamp((int)(Next() * list.Count), 0, list.Count - 1)];
    }
}

public class UnitDef {
    public string id, name, desc;
    public int n;
    public float hp, dmg, cd, spd;      // spd 單位：格/秒
    public bool ranged;
    public float range, volleyCd;       // range 單位：格
}

public static class Defs {
    public static readonly Dictionary<string, UnitDef> Types = new Dictionary<string, UnitDef> {
        { "infantry", new UnitDef { id = "infantry", name = "劍士", desc = "均衡近戰主力",
            n = 9, hp = 3f, dmg = 1f, cd = 0.8f, spd = 1.53f } },
        { "archer", new UnitDef { id = "archer", name = "弓兵", desc = "遠程齊射，近戰脆弱",
            n = 8, hp = 2.4f, dmg = 0.45f, cd = 0.9f, spd = 1.47f,
            ranged = true, range = 5.2f, volleyCd = 2.6f } },
        { "pike", new UnitDef { id = "pike", name = "長槍兵", desc = "重擊緩慢，正面堅實",
            n = 8, hp = 3.6f, dmg = 1.5f, cd = 1.15f, spd = 1.27f } },
    };
    public static readonly string[] EnemyTypes = { "infantry", "archer", "pike" };
}

public class SkillDef {
    public string id, name, desc;
    public bool targeted;
    public float cd;
    public string[] allow;
}

public static class Skills {
    public static readonly Dictionary<string, SkillDef> All = new Dictionary<string, SkillDef> {
        { "charge", new SkillDef { id = "charge", name = "衝鋒", targeted = true, cd = 16,
            allow = new[] { "infantry", "pike" },
            desc = "朝目標方向猛衝，撞擊敵兵並將其擊退——推下海即溺斃。" } },
        { "volley", new SkillDef { id = "volley", name = "箭雨", targeted = true, cd = 15,
            allow = new[] { "archer" },
            desc = "對目標區域傾瀉密集箭矢。" } },
        { "wall", new SkillDef { id = "wall", name = "盾牆", targeted = false, cd = 18,
            allow = new[] { "infantry", "pike" },
            desc = "原地結陣 5 秒，受到的傷害降低 65%。" } },
        { "rally", new SkillDef { id = "rally", name = "集結", targeted = false, cd = 50,
            allow = new[] { "infantry", "archer", "pike" },
            desc = "治癒全隊並補充最多 3 名倒下的士兵。" } },
    };
}

public class RosterSquad {
    public int id;
    public string type;
    public int vet;
    public string skill;
    public bool alive = true;
    public int bonusN;
}

public class CampNode {
    public string type;   // start / isle / rich / hard / fort
    public int diff;
    public bool cleared;
    public int seedOff;
}

public static class NodeMeta {
    public static string Name(string type) {
        switch (type) {
            case "start": return "前哨島";
            case "rich":  return "富庶島";
            case "hard":  return "險惡島";
            case "fort":  return "要塞";
            default:      return "小島";
        }
    }
}

public class RunState {
    public uint seed;
    public int layer, conquered;
    public List<List<CampNode>> campaign;
    public List<RosterSquad> roster;
    public Rng rng;
    static int seq = 1;

    public static RosterSquad MkRosterSquad(string type) {
        return new RosterSquad { id = seq++, type = type };
    }
    public static int MaxN(RosterSquad rs) {
        return Defs.Types[rs.type].n + rs.vet + rs.bonusN;
    }
    public static string Label(RosterSquad rs) {
        string stars = "";
        for (int i = 0; i < rs.vet; i++) stars += "★";
        return Defs.Types[rs.type].name + stars;
    }

    public static RunState New(uint seed) {
        var r = new RunState {
            seed = seed,
            rng = new Rng(seed),
            roster = new List<RosterSquad> { MkRosterSquad("infantry"), MkRosterSquad("archer") },
        };
        r.campaign = GenCampaign(r.rng);
        return r;
    }

    // 起始島 → 5 層每層 2 選 1 → 要塞
    static List<List<CampNode>> GenCampaign(Rng rng) {
        var layers = new List<List<CampNode>>();
        layers.Add(new List<CampNode> { new CampNode { type = "start", diff = 0 } });
        for (int i = 1; i <= 5; i++) {
            var l = new List<CampNode>();
            for (int k = 0; k < 2; k++) {
                float v = rng.Next();
                if (v < 0.30f)      l.Add(new CampNode { type = "rich", diff = i });
                else if (v < 0.55f) l.Add(new CampNode { type = "hard", diff = i + 2 });
                else                l.Add(new CampNode { type = "isle", diff = i });
            }
            layers.Add(l);
        }
        layers.Add(new List<CampNode> { new CampNode { type = "fort", diff = 8 } });
        int idx = 0;
        foreach (var l in layers) foreach (var n in l) { n.seedOff = idx * 7919; idx++; }
        return layers;
    }
}

}
