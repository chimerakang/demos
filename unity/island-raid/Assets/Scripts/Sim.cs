// 戰鬥模擬：小隊 / 士兵個體 / 箭矢 / 佔領 / 守軍 AI / 技能
// 距離單位皆為「格」（1 格 = 1 世界單位）；由 game.js 原型 1:1 移植（px/30）
using System;
using System.Collections.Generic;
using UnityEngine;

namespace IslandRaid {

public enum Side { Player, Enemy }

public class Knockback { public float dx, dy, left; }
public class ChargeState {
    public float dx, dy, left;
    public HashSet<Soldier> hit = new HashSet<Soldier>();
}

public class Soldier {
    public float x, y, hp, cd;
    public int slot;
    public Knockback kb;
}

public class Squad {
    public Side side;
    public string type;
    public UnitDef def;
    public RosterSquad roster;
    public int vet, maxN;
    public float x, y;
    public List<Vector2Int> path = new List<Vector2Int>();
    public List<Soldier> soldiers = new List<Soldier>();
    public bool engaged, dead, onBoat;
    public string skill;
    public float skillCd, wallT, volleyT, repathT;
    public ChargeState charge;
    public bool aiAttack;      // 守軍：false=駐防 true=進攻
    public Squad aiTarget;
    public Vector2Int moveMark;
    public float moveMarkT = 99f;
}

public class Boat {
    public Squad squad;
    public float x, y, bob;
    public List<Vector2Int> path = new List<Vector2Int>();
    public string state = "idle";   // idle / sail / landed
    public Tile beach;
}

public class Arrow {
    public float sx, sy, tx, ty, t, dur, dmg;
    public Side side;
}

public class Wave { public float t; public bool done; }
public class PendingArrow { public float at, sx, sy, tx, ty, dmg; public Side side; }

public class Battle {
    public const float AGGRO = 4.6f;
    public const float CAPTURE_TIME = 4.5f;

    public CampNode node;
    public Island island;
    public RunState run;
    public Rng rng;
    public float time, endT;
    public bool over, surrendered, finished;
    public string result;
    public List<Squad> squads = new List<Squad>();
    public List<Boat> boats = new List<Boat>();
    public List<Arrow> arrows = new List<Arrow>();
    public List<Wave> waves = new List<Wave>();
    public List<PendingArrow> pending = new List<PendingArrow>();

    public Action<string, Color, float> OnMsg = (m, c, d) => { };
    public Action<string, float, float> OnFx = (t, x, y) => { };   // ring / splash / slash / puff
    public Action OnRosterChanged = () => { };

    static List<Vector2>[] slotCache = new List<Vector2>[64];
    public static List<Vector2> SlotOffsets(int n) {
        n = Mathf.Clamp(n, 1, 63);
        if (slotCache[n] != null) return slotCache[n];
        var outp = new List<Vector2> { Vector2.zero };
        for (int ring = 1; outp.Count < n; ring++) {
            int cnt = ring * 6;
            for (int i = 0; i < cnt && outp.Count < n; i++) {
                float a = (float)i / cnt * Mathf.PI * 2 + ring;
                outp.Add(new Vector2(Mathf.Cos(a) * ring * 0.25f, Mathf.Sin(a) * ring * 0.25f));
            }
        }
        slotCache[n] = outp;
        return outp;
    }

    public Battle(RunState runState, CampNode campNode) {
        run = runState;
        node = campNode;
        rng = run.rng;
        island = IslandGen.Generate(node.diff, (uint)(run.seed + (uint)node.seedOff + 1u));

        // 守軍
        int d = node.diff;
        int nDef = 2 + Mathf.RoundToInt(d * 0.9f);
        var spots = new List<Tile>();
        foreach (var h in island.houses) spots.Add(h.tile);
        var landTiles = new List<Tile>();
        for (int y = 0; y < Island.H; y++)
            for (int x = 0; x < Island.W; x++)
                if (island.tiles[y, x].h >= 2) landTiles.Add(island.tiles[y, x]);
        for (int i = 0; i < nDef; i++) {
            Tile baseT = spots.Count > 0 ? spots[i % spots.Count] : rng.Pick(landTiles);
            Tile t0 = IslandGen.NearestReachable(island,
                baseT.x + rng.RangeInt(-2, 2), baseT.y + rng.RangeInt(-2, 2)) ?? baseT;
            string type = d >= 3 ? rng.Pick(Defs.EnemyTypes)
                : rng.Pick(new[] { "infantry", "infantry", "archer" });
            int vet = (d >= 4 && rng.Next() < 0.25f + d * 0.05f) ? 1 : 0;
            int n = Defs.Types[type].n - 2 + vet + Mathf.Min(3, d >> 1);
            squads.Add(MkSquad(Side.Enemy, type, t0.x + 0.5f, t0.y + 0.5f, vet, n, null));
        }

        // 敵援軍船班
        if (d >= 3) waves.Add(new Wave { t = 50 });
        if (d >= 6) waves.Add(new Wave { t = 95 });
        if (node.type == "fort") waves.Add(new Wave { t = 140 });

        // 玩家登陸艇：沿下緣海面排開
        var alive = run.roster.FindAll(r => r.alive);
        for (int i = 0; i < alive.Count; i++) {
            var rs = alive[i];
            float bx = (float)Island.W / (alive.Count + 1) * (i + 1);
            float by = Island.H - 1 + 0.5f;
            var sq = MkSquad(Side.Player, rs.type, bx, by, rs.vet, RunState.MaxN(rs), rs);
            sq.onBoat = true;
            squads.Add(sq);
            boats.Add(new Boat { squad = sq, x = bx, y = by, bob = rng.Range(0, 6.28f) });
        }
    }

    public Squad MkSquad(Side side, string type, float x, float y, int vet, int n, RosterSquad roster) {
        var def = Defs.Types[type];
        var s = new Squad {
            side = side, type = type, def = def, roster = roster, vet = vet,
            x = x, y = y, maxN = n,
            skill = roster != null ? roster.skill : null,
            volleyT = rng.Range(1f, 2.5f),
        };
        var slots = SlotOffsets(n);
        for (int i = 0; i < n; i++)
            s.soldiers.Add(new Soldier {
                x = x + slots[i].x, y = y + slots[i].y,
                hp = def.hp + (vet > 0 ? 1 : 0), cd = rng.Range(0, 0.5f), slot = i,
            });
        return s;
    }

    static float Dist(float ax, float ay, float bx, float by) {
        float dx = ax - bx, dy = ay - by;
        return Mathf.Sqrt(dx * dx + dy * dy);
    }

    public void OrderMove(Squad s, int tx, int ty) {
        var goal = island.Get(tx, ty);
        if (goal == null) return;
        if (goal.h <= 0) {
            goal = IslandGen.NearestReachable(island, tx, ty);
            if (goal == null) return;
        }
        var cur = island.At(s.x, s.y);
        if (cur == null) return;
        var p = IslandGen.FindPath(island, cur.x, cur.y, goal.x, goal.y, false);
        if (p != null) {
            s.path = p;
            s.moveMark = new Vector2Int(goal.x, goal.y);
            s.moveMarkT = 0;
        }
    }

    // 下令搶灘；回傳是否成功
    public bool OrderLanding(Squad s, Tile clicked) {
        Tile beach = clicked.beach ? clicked : null;
        if (beach == null) {
            float bd = 2.6f;
            foreach (var bt in island.beaches) {
                float d = Dist(bt.x, bt.y, clicked.x, clicked.y);
                if (d < bd) { bd = d; beach = bt; }
            }
        }
        if (beach == null) return false;
        var boat = boats.Find(b2 => b2.squad == s);
        if (boat == null) return false;
        Tile landing = null;
        int[,] DIR = { { 0, 1 }, { 1, 0 }, { -1, 0 }, { 0, -1 } };
        for (int i = 0; i < 4; i++) {
            var n = island.Get(beach.x + DIR[i, 0], beach.y + DIR[i, 1]);
            if (n != null && n.ocean) { landing = n; break; }
        }
        if (landing == null) return false;
        var bTile = island.At(boat.x, boat.y);
        if (bTile == null) return false;
        var p = IslandGen.FindPath(island, bTile.x, bTile.y, landing.x, landing.y, true);
        if (p == null) return false;
        boat.path = p;
        boat.state = "sail";
        boat.beach = beach;
        s.moveMark = new Vector2Int(beach.x, beach.y);
        s.moveMarkT = 0;
        return true;
    }

    public void Update(float dt) {
        time += dt;

        // 船
        foreach (var bt in boats) {
            bt.bob += dt * 2;
            if (bt.state == "sail" && bt.path.Count > 0) {
                var wp = bt.path[0];
                float px = wp.x + 0.5f, py = wp.y + 0.5f;
                float d = Dist(bt.x, bt.y, px, py);
                const float spd = 2.33f;
                if (d < spd * dt) {
                    bt.x = px; bt.y = py; bt.path.RemoveAt(0);
                    if (bt.path.Count == 0) {
                        bt.state = "landed";
                        bt.squad.onBoat = false;
                        bt.squad.x = bt.beach.x + 0.5f;
                        bt.squad.y = bt.beach.y + 0.5f;
                        foreach (var so in bt.squad.soldiers) { so.x = bt.x; so.y = bt.y; }
                        OnFx("ring", bt.squad.x, bt.squad.y);
                    }
                } else {
                    bt.x += (px - bt.x) / d * spd * dt;
                    bt.y += (py - bt.y) / d * spd * dt;
                }
            }
            if (bt.state != "landed") { bt.squad.x = bt.x; bt.squad.y = bt.y - 0.13f; }
        }

        // 援軍
        foreach (var w in waves)
            if (!w.done && time >= w.t) { w.done = true; SpawnWave(); }

        // 延遲箭雨
        for (int i = pending.Count - 1; i >= 0; i--) {
            if (time >= pending[i].at) {
                var p = pending[i];
                FireArrow(p.sx, p.sy, p.tx, p.ty, p.side, p.dmg);
                pending.RemoveAt(i);
            }
        }

        var alive = squads.FindAll(s => !s.dead);
        foreach (var s in alive) {
            if (s.onBoat || s.dead) continue;
            s.skillCd = Mathf.Max(0, s.skillCd - dt);
            s.wallT = Mathf.Max(0, s.wallT - dt);
            s.moveMarkT += dt;

            // 交戰判定
            s.engaged = false;
            foreach (var o in alive) {
                if (o.side == s.side || o.dead || o.onBoat) continue;
                if (Dist(s.x, s.y, o.x, o.y) < 1.35f) { s.engaged = true; break; }
            }

            // 衝鋒
            if (s.charge != null) {
                var c = s.charge;
                float step = 5.67f * dt;
                float nx = s.x + c.dx * step, ny = s.y + c.dy * step;
                var nt = island.At(nx, ny);
                if (nt == null || nt.h <= 0) c.left = 0;   // 岸邊煞停
                else { s.x = nx; s.y = ny; }
                c.left -= step;
                foreach (var o in alive) {
                    if (o.side == s.side || o.dead || o.onBoat) continue;
                    foreach (var so in o.soldiers) {
                        if (c.hit.Contains(so)) continue;
                        if (Dist(so.x, so.y, s.x, s.y) < 0.9f) {
                            c.hit.Add(so);
                            so.hp -= 1.5f + (s.vet > 0 ? 0.5f : 0);
                            so.kb = new Knockback { dx = c.dx, dy = c.dy, left = 1.05f };
                            OnFx("slash", so.x, so.y);
                        }
                    }
                }
                if (c.left <= 0) s.charge = null;
            }
            else if (!s.engaged && s.path.Count > 0 && s.wallT <= 0) {
                var wp = s.path[0];
                float px = wp.x + 0.5f, py = wp.y + 0.5f;
                var cur = island.At(s.x, s.y);
                var nxt = island.Get(wp.x, wp.y);
                bool climb = cur != null && nxt != null && nxt.h > cur.h;
                float spd = s.def.spd * (climb ? 0.55f : 1f);
                float d = Dist(s.x, s.y, px, py);
                if (d < spd * dt) { s.x = px; s.y = py; s.path.RemoveAt(0); }
                else { s.x += (px - s.x) / d * spd * dt; s.y += (py - s.y) / d * spd * dt; }
            }

            // 弓兵齊射
            if (s.def.ranged && !s.engaged && s.charge == null) {
                s.volleyT -= dt;
                if (s.volleyT <= 0) {
                    Squad tgt = null; float bd = float.MaxValue;
                    foreach (var o in alive) {
                        if (o.side == s.side || o.dead || o.onBoat) continue;
                        float d = Dist(s.x, s.y, o.x, o.y);
                        if (d < s.def.range && d < bd) { bd = d; tgt = o; }
                    }
                    if (tgt != null && tgt.soldiers.Count > 0) {
                        s.volleyT = s.def.volleyCd;
                        foreach (var so in s.soldiers) {
                            var v = tgt.soldiers[Mathf.Clamp((int)(rng.Next() * tgt.soldiers.Count), 0, tgt.soldiers.Count - 1)];
                            FireArrow(so.x, so.y, v.x + rng.Range(-0.3f, 0.3f), v.y + rng.Range(-0.3f, 0.3f),
                                s.side, s.def.dmg * 2 + (s.vet > 0 ? 0.3f : 0));
                        }
                    } else s.volleyT = 0.4f;
                }
            }

            // 士兵層
            UpdateSoldiers(s, alive, dt);
            if (s.soldiers.Count == 0) {
                s.dead = true;
                if (s.roster != null) {
                    s.roster.alive = false;
                    OnMsg(RunState.Label(s.roster) + " 小隊全滅…", new Color(1f, 0.62f, 0.58f), 2.5f);
                }
                OnFx("ring", s.x, s.y);
                OnRosterChanged();
            }
        }

        AiTick(dt, alive);
        UpdateCapture(dt, alive);
        UpdateArrows(dt, alive);

        // 勝負
        if (!over) {
            bool pAlive = squads.Exists(s => s.side == Side.Player && !s.dead);
            bool eAlive = squads.Exists(s => s.side == Side.Enemy && !s.dead);
            bool allCap = island.houses.TrueForAll(h => h.captured);
            if (allCap && !surrendered) {
                surrendered = true;
                waves.Clear();
                if (eAlive) OnMsg("據點全數易幟！肅清殘餘守軍", new Color(1f, 0.91f, 0.66f), 3f);
            }
            bool wavePending = waves.Exists(w => !w.done);
            if (!pAlive) { over = true; result = "lose"; }
            else if (allCap && !eAlive && !wavePending) { over = true; result = "win"; }
            if (over) endT = 1.6f;
        } else {
            endT -= dt;
            if (endT <= 0) finished = true;
        }
    }

    void UpdateSoldiers(Squad s, List<Squad> alive, float dt) {
        var slots = SlotOffsets(s.maxN);
        var foes = new List<Squad>();
        foreach (var o in alive) {
            if (o.side == s.side || o.dead || o.onBoat) continue;
            if (Dist(s.x, s.y, o.x, o.y) < 3.2f) foes.Add(o);
        }
        foreach (var so in s.soldiers) {
            so.cd = Mathf.Max(0, so.cd - dt);
            if (so.kb != null) {
                float step = 4.67f * dt;
                so.x += so.kb.dx * step; so.y += so.kb.dy * step; so.kb.left -= step;
                if (so.kb.left <= 0) {
                    so.kb = null;
                    var t0 = island.At(so.x, so.y);
                    if (t0 == null || t0.h <= 0) { so.hp = 0; OnFx("splash", so.x, so.y); }
                }
                continue;
            }
            Soldier tgt = null; float bd = float.MaxValue;
            if ((foes.Count > 0 && s.wallT <= 0) || s.engaged) {
                foreach (var o in foes)
                    foreach (var v in o.soldiers) {
                        float d = Dist(so.x, so.y, v.x, v.y);
                        if (d < bd && d < 1.9f) { bd = d; tgt = v; }
                    }
            }
            if (tgt != null) {
                if (bd > 0.27f) {
                    float step = (s.def.spd + 0.4f) * dt;
                    so.x += (tgt.x - so.x) / bd * step;
                    so.y += (tgt.y - so.y) / bd * step;
                } else if (so.cd <= 0) {
                    so.cd = s.def.cd;
                    float dmg = s.def.dmg * (s.vet > 0 ? 1.25f : 1f);
                    var os = FindOwner(tgt, alive);
                    if (os != null && os.wallT > 0) dmg *= 0.35f;
                    tgt.hp -= dmg;
                    OnFx("slash", tgt.x, tgt.y);
                    if (os != null && os.side == Side.Enemy) AggroDefender(os, s);
                }
            } else {
                var off = slots[so.slot % slots.Count];
                float px = s.x + off.x, py = s.y + off.y;
                float d = Dist(so.x, so.y, px, py);
                if (d > 0.067f) {
                    float step = Mathf.Min((s.def.spd + 0.87f) * dt, d);
                    so.x += (px - so.x) / d * step;
                    so.y += (py - so.y) / d * step;
                }
            }
            // 誤入水中 → 拉回最近陸地
            var wt = island.At(so.x, so.y);
            if (wt != null && wt.h <= 0 && so.kb == null) {
                var back = IslandGen.NearestReachable(island, wt.x, wt.y);
                if (back != null) {
                    float k = Mathf.Min(1f, 12f * dt);
                    so.x += ((back.x + 0.5f) - so.x) * k;
                    so.y += ((back.y + 0.5f) - so.y) * k;
                }
            }
        }
        s.soldiers.RemoveAll(so => so.hp <= 0);
    }

    Squad FindOwner(Soldier soldier, List<Squad> alive) {
        foreach (var s in alive) if (s.soldiers.Contains(soldier)) return s;
        return null;
    }

    void AggroDefender(Squad es, Squad from) {
        if (!es.aiAttack) { es.aiAttack = true; es.aiTarget = from; }
    }

    void AiTick(float dt, List<Squad> alive) {
        foreach (var s in alive) {
            if (s.side != Side.Enemy || s.onBoat || s.dead) continue;
            s.repathT -= dt;
            if (s.repathT > 0) continue;
            s.repathT = 0.6f;
            var players = alive.FindAll(o => o.side == Side.Player && !o.onBoat && !o.dead);
            if (players.Count == 0) { s.path.Clear(); continue; }
            Squad near = null; float bd = float.MaxValue;
            foreach (var p in players) {
                float d = Dist(s.x, s.y, p.x, p.y);
                if (d < bd) { bd = d; near = p; }
            }
            if (!s.aiAttack) {
                if (bd < AGGRO) { s.aiAttack = true; s.aiTarget = near; }
                else {
                    var contested = island.houses.Find(h => !h.captured && h.progress > 0);
                    if (contested != null) { s.aiAttack = true; s.aiTarget = near; }
                }
            }
            if (s.aiAttack) {
                if (s.aiTarget == null || s.aiTarget.dead || s.aiTarget.onBoat) s.aiTarget = near;
                var tgt = s.aiTarget;
                if (tgt == null) { s.aiAttack = false; continue; }
                float td = Dist(s.x, s.y, tgt.x, tgt.y);
                if (s.def.ranged && td < s.def.range * 0.9f && td > 1.6f) { s.path.Clear(); continue; }
                if (td > 1.1f) {
                    var ct = island.At(s.x, s.y);
                    var tt = island.At(tgt.x, tgt.y);
                    if (ct != null && tt != null) {
                        var p = IslandGen.FindPath(island, ct.x, ct.y, tt.x, tt.y, false);
                        if (p != null) s.path = p.GetRange(0, Mathf.Min(10, p.Count));
                    }
                } else s.path.Clear();
            }
        }
    }

    void SpawnWave() {
        if (island.beaches.Count == 0) return;
        var beach = rng.Pick(island.beaches);
        int d = node.diff;
        string type = rng.Pick(Defs.EnemyTypes);
        int vet = d >= 5 ? 1 : 0;
        int n = Defs.Types[type].n - 1 + Mathf.Min(3, d >> 1);
        var sq = MkSquad(Side.Enemy, type, beach.x + 0.5f, beach.y + 0.5f, vet, n, null);
        sq.aiAttack = true;
        squads.Add(sq);
        OnFx("ring", sq.x, sq.y);
        OnMsg("敵方援軍登陸！", new Color(1f, 0.62f, 0.58f), 2.5f);
    }

    void UpdateCapture(float dt, List<Squad> alive) {
        foreach (var h in island.houses) {
            if (h.captured) continue;
            float hx = h.tile.x + 0.5f, hy = h.tile.y + 0.5f;
            bool pNear = alive.Exists(s => s.side == Side.Player && !s.dead && !s.onBoat
                && Dist(s.x, s.y, hx, hy) < 1.1f);
            bool eNear = alive.Exists(s => s.side == Side.Enemy && !s.dead
                && Dist(s.x, s.y, hx, hy) < 2.4f);
            if (pNear && !eNear) {
                h.progress += dt / CAPTURE_TIME;
                if (h.progress >= 1) {
                    h.captured = true; h.progress = 1;
                    OnFx("ring", hx, hy);
                    OnMsg("據點佔領！", new Color(0.81f, 0.89f, 1f), 1.6f);
                }
            } else if (h.progress > 0 && !pNear) {
                h.progress = Mathf.Max(0, h.progress - dt / CAPTURE_TIME * 0.7f);
            }
        }
    }

    void FireArrow(float sx, float sy, float tx, float ty, Side side, float dmg) {
        float d = Dist(sx, sy, tx, ty);
        arrows.Add(new Arrow { sx = sx, sy = sy, tx = tx, ty = ty, dur = 0.35f + d * 0.115f, side = side, dmg = dmg });
    }

    void UpdateArrows(float dt, List<Squad> alive) {
        for (int i = arrows.Count - 1; i >= 0; i--) {
            var a = arrows[i];
            a.t += dt;
            if (a.t >= a.dur) {
                Soldier v = null; float bd = 0.4f; Squad os = null;
                foreach (var s in alive) {
                    if (s.side == a.side || s.dead || s.onBoat) continue;
                    foreach (var so in s.soldiers) {
                        float d = Dist(so.x, so.y, a.tx, a.ty);
                        if (d < bd) { bd = d; v = so; os = s; }
                    }
                }
                if (v != null) {
                    float dmg = a.dmg;
                    if (os.wallT > 0) dmg *= 0.35f;
                    v.hp -= dmg;
                    OnFx("slash", v.x, v.y);
                    if (os.side == Side.Enemy) AggroDefender(os, null);
                } else OnFx("puff", a.tx, a.ty);
                arrows.RemoveAt(i);
            }
        }
    }

    public void UseSkill(Squad s, float tx = float.NaN, float ty = float.NaN) {
        if (s.skill == null || !Skills.All.ContainsKey(s.skill) || s.skillCd > 0) return;
        var sk = Skills.All[s.skill];
        if (sk.targeted && float.IsNaN(tx)) return;
        s.skillCd = sk.cd;
        if (s.skill == "charge") {
            float dx = tx - s.x, dy = ty - s.y;
            float d = Mathf.Max(0.001f, Mathf.Sqrt(dx * dx + dy * dy));
            s.charge = new ChargeState { dx = dx / d, dy = dy / d, left = Mathf.Min(d, 3.4f) };
            s.path.Clear();
            OnFx("ring", s.x, s.y);
        } else if (s.skill == "volley") {
            for (int i = 0; i < 14; i++) {
                float ang = rng.Range(0, 6.28f), r = rng.Range(0, 1.25f);
                pending.Add(new PendingArrow {
                    at = time + i * 0.09f,
                    sx = s.x + rng.Range(-0.27f, 0.27f), sy = s.y - 0.2f,
                    tx = tx + Mathf.Cos(ang) * r, ty = ty + Mathf.Sin(ang) * r,
                    side = s.side, dmg = 1.4f,
                });
            }
            OnFx("ring", tx, ty);
        } else if (s.skill == "wall") {
            s.wallT = 5;
            s.path.Clear();
            OnFx("ring", s.x, s.y);
        } else if (s.skill == "rally") {
            foreach (var so in s.soldiers) so.hp = s.def.hp + (s.vet > 0 ? 1 : 0);
            int need = Mathf.Min(3, s.maxN - s.soldiers.Count);
            while (need-- > 0)
                s.soldiers.Add(new Soldier {
                    x = s.x + rng.Range(-0.2f, 0.2f), y = s.y + rng.Range(-0.2f, 0.2f),
                    hp = s.def.hp + (s.vet > 0 ? 1 : 0), slot = s.soldiers.Count,
                });
            OnFx("ring", s.x, s.y);
        }
    }
}

}
