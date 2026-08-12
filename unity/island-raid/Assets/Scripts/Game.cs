// 主控制器：畫面狀態機 / IMGUI 介面 / 輸入 / roguelike 獎勵流程
using System;
using System.Collections.Generic;
using UnityEngine;

namespace IslandRaid {

public static class Bootstrap {
    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
    static void Init() {
        if (UnityEngine.Object.FindFirstObjectByType<Game>() != null) return;
        var go = new GameObject("Game");
        go.AddComponent<Game>();
    }
}

public class Game : MonoBehaviour {
    enum Scr { Title, Campaign, Battle, Reward, End }

    class CardEntry { public string id, skillId, title, desc, tag; }

    Scr scr = Scr.Title;
    RunState run;
    Battle battle;
    View view;
    Squad selected;
    bool targeting;
    string seedInput = "";
    Font uiFont;

    string msgText = ""; Color msgColor = Color.white; float msgT;

    readonly List<CardEntry> rewardCards = new List<CardEntry>();
    int picksLeft; bool rewardBetter; string rewardSub = "";

    bool modalActive; string modalTitle = "";
    List<RosterSquad> modalList; Action<RosterSquad> modalCb;

    bool endWin;

    // styles
    bool stylesReady;
    GUIStyle stTitle, stSub, stH2, stMsg, stCard, stChip, stBadge, stBox, stBtn, stSmall;

    void Awake() {
        Application.targetFrameRate = 60;
        uiFont = Resources.Load<Font>("NotoSansTC");
        view = new View();
        view.SetupScene();
    }

    void Update() {
        float dt = Mathf.Min(0.05f, Time.deltaTime);
        msgT = Mathf.Max(0, msgT - dt);
        if (scr == Scr.Battle && battle != null) {
            battle.Update(dt);
            view.Sync(battle, selected, dt);
            if (battle.finished) { FinishBattle(); return; }

            // 快捷鍵
            for (int i = 0; i < 4; i++)
                if (Input.GetKeyDown(KeyCode.Alpha1 + i)) {
                    var ps = battle.squads.FindAll(s => s.side == Side.Player);
                    if (i < ps.Count && !ps[i].dead) { selected = ps[i]; targeting = false; }
                }
            if (Input.GetKeyDown(KeyCode.Q)) SkillButtonPress();
        }
    }

    /* ---------- 流程 ---------- */

    void NewRun(uint seed) {
        run = RunState.New(seed);
        scr = Scr.Campaign;
    }

    void StartBattle(CampNode node) {
        var b = new Battle(run, node);
        b.OnMsg = ShowMsg;
        b.OnFx = (t, x, y) => view.AddFx(b, t, x, y);
        battle = b;
        selected = null;
        targeting = false;
        view.BuildIsland(b.island);
        scr = Scr.Battle;
        ShowMsg("搶灘登陸！點選小隊 → 點擊灘頭", new Color(1f, 0.91f, 0.66f), 3.2f);
    }

    void FinishBattle() {
        var b = battle;
        battle = null;
        view.ClearBattle();
        selected = null;
        if (b.result == "win") {
            b.node.cleared = true;
            run.conquered++;
            if (b.node.type == "fort") { endWin = true; scr = Scr.End; return; }
            run.layer++;
            BuildRewardCards(b.node.type == "rich" ? 2 : 1, b.node.type == "hard");
            scr = Scr.Reward;
        } else {
            endWin = false;
            scr = Scr.End;
        }
    }

    void ShowMsg(string t, Color c, float dur) { msgText = t; msgColor = c; msgT = dur; }

    /* ---------- 獎勵卡 ---------- */

    bool CardOk(string id) {
        switch (id) {
            case "recruit": return run.roster.FindAll(r => r.alive).Count < 4;
            case "vet":     return run.roster.Exists(r => r.alive && r.vet < 2);
            case "skill":   return run.roster.Exists(r => r.alive && r.skill == null);
            default:        return true;
        }
    }

    CardEntry MkCard(string id, bool better) {
        if (id == "skill") {
            var keys = new List<string>(Skills.All.Keys);
            string sid = run.rng.Pick(keys);
            return new CardEntry { id = id, skillId = sid, title = "卷軸：" + Skills.All[sid].name,
                desc = Skills.All[sid].desc, tag = "技能" };
        }
        switch (id) {
            case "recruit": return new CardEntry { id = id, title = "援軍小隊",
                desc = "一支新的小隊加入遠征（隨機兵種）。", tag = "新戰力" };
            case "vet": return new CardEntry { id = id, title = "老兵勳章",
                desc = "選一支小隊晉升老兵：+傷害、+體力、+1 人。", tag = "強化" };
            default: return new CardEntry { id = "banner", title = "軍旗",
                desc = "所有小隊編制 +1 人。", tag = "全體" };
        }
    }

    void BuildRewardCards(int picks, bool better) {
        rewardCards.Clear();
        picksLeft = picks;
        rewardBetter = better;
        rewardSub = picks > 1 ? "富庶之島——可選擇 " + picks + " 項戰利品" : "選擇一項戰利品";
        var pool = new List<string>();
        foreach (var id in new[] { "recruit", "vet", "skill", "banner" })
            if (CardOk(id)) pool.Add(id);
        while (rewardCards.Count < 3) {
            string id = pool.Count > 0 ? pool[Mathf.Clamp((int)(run.rng.Next() * pool.Count), 0, pool.Count - 1)] : "banner";
            pool.Remove(id);
            rewardCards.Add(MkCard(id, better));
        }
    }

    void ApplyCard(CardEntry c, Action done) {
        if (c.id == "recruit") {
            var rs = RunState.MkRosterSquad(run.rng.Pick(new[] { "infantry", "archer", "pike" }));
            if (rewardBetter) rs.vet = 1;
            run.roster.Add(rs);
            done();
        } else if (c.id == "banner") {
            foreach (var r in run.roster) if (r.alive) r.bonusN++;
            done();
        } else if (c.id == "vet") {
            PickSquadModal("選擇要晉升的小隊",
                run.roster.FindAll(r => r.alive && r.vet < 2),
                rs => { rs.vet = Mathf.Min(2, rs.vet + (rewardBetter ? 2 : 1)); done(); },
                done);
        } else if (c.id == "skill") {
            var sk = Skills.All[c.skillId];
            var cands = run.roster.FindAll(r => r.alive && r.skill == null
                && Array.IndexOf(sk.allow, r.type) >= 0);
            if (cands.Count == 0) {   // 沒有適合的小隊 → 換成軍旗效果
                foreach (var r in run.roster) if (r.alive) r.bonusN++;
                done();
                return;
            }
            PickSquadModal("把「" + sk.name + "」交給誰？", cands,
                rs => { rs.skill = c.skillId; done(); }, done);
        }
    }

    void PickSquadModal(string title, List<RosterSquad> list, Action<RosterSquad> cb, Action fallback) {
        if (list.Count == 0) { fallback(); return; }
        modalActive = true;
        modalTitle = title;
        modalList = list;
        modalCb = cb;
    }

    /* ---------- 輸入 ---------- */

    void SkillButtonPress() {
        var s = selected;
        if (s == null || s.dead || s.skill == null || s.skillCd > 0 || s.onBoat) return;
        var sk = Skills.All[s.skill];
        if (sk.targeted) targeting = !targeting;
        else battle.UseSkill(s);
    }

    void WorldClick() {
        if (battle == null || battle.over || view.cam == null) return;
        var ray = view.cam.ScreenPointToRay(Input.mousePosition);
        RaycastHit hit;
        if (!Physics.Raycast(ray, out hit, 200f)) return;
        Vector2 sim = View.Sim(hit.point);
        float simX = sim.x, simY = sim.y;
        var tref = hit.collider.GetComponent<TileRef>();
        Tile tile = tref != null ? battle.island.Get(tref.x, tref.y) : battle.island.At(simX, simY);
        if (tile == null) return;

        // 技能瞄準
        if (targeting && selected != null && !selected.dead) {
            battle.UseSkill(selected, simX, simY);
            targeting = false;
            return;
        }

        // 點到玩家小隊 → 選取
        Squad hitSq = null; float bd = 1.1f;
        foreach (var s in battle.squads) {
            if (s.side != Side.Player || s.dead) continue;
            float dx = s.x - simX, dy = s.y - simY;
            float d = Mathf.Sqrt(dx * dx + dy * dy);
            if (d < bd) { bd = d; hitSq = s; }
        }
        if (hitSq != null) { selected = hitSq; targeting = false; return; }

        var sel = selected;
        if (sel == null || sel.dead) return;
        if (sel.onBoat) {
            if (!battle.OrderLanding(sel, tile))
                ShowMsg("請點選灘頭（淺色沙岸）", new Color(1f, 0.91f, 0.66f), 1.6f);
        } else {
            battle.OrderMove(sel, tile.x, tile.y);
        }
    }

    /* ---------- IMGUI ---------- */

    void EnsureStyles() {
        if (stylesReady) return;
        stylesReady = true;
        stTitle = new GUIStyle(GUI.skin.label) { fontSize = 44, alignment = TextAnchor.MiddleCenter, fontStyle = FontStyle.Bold };
        stSub = new GUIStyle(GUI.skin.label) { fontSize = 15, alignment = TextAnchor.MiddleCenter, richText = true, wordWrap = true };
        stH2 = new GUIStyle(GUI.skin.label) { fontSize = 26, alignment = TextAnchor.MiddleCenter, fontStyle = FontStyle.Bold };
        stMsg = new GUIStyle(GUI.skin.label) { fontSize = 24, alignment = TextAnchor.MiddleCenter, fontStyle = FontStyle.Bold };
        stCard = new GUIStyle(GUI.skin.button) { fontSize = 13, alignment = TextAnchor.UpperLeft, wordWrap = true, richText = true, padding = new RectOffset(12, 12, 12, 12) };
        stChip = new GUIStyle(GUI.skin.button) { fontSize = 12, alignment = TextAnchor.UpperLeft, richText = true, padding = new RectOffset(8, 8, 6, 6) };
        stBadge = new GUIStyle(GUI.skin.label) { fontSize = 11, alignment = TextAnchor.MiddleCenter, fontStyle = FontStyle.Bold };
        stBox = new GUIStyle(GUI.skin.box) { fontSize = 12, alignment = TextAnchor.UpperRight, richText = true, padding = new RectOffset(10, 10, 8, 8) };
        stBtn = new GUIStyle(GUI.skin.button) { fontSize = 16 };
        stSmall = new GUIStyle(GUI.skin.label) { fontSize = 12, alignment = TextAnchor.MiddleCenter, wordWrap = true };
    }

    void OnGUI() {
        if (uiFont != null) GUI.skin.font = uiFont;
        EnsureStyles();
        float gs = Mathf.Clamp(Screen.height / 720f, 0.55f, 2.2f);
        GUI.matrix = Matrix4x4.Scale(new Vector3(gs, gs, 1));
        float vw = Screen.width / gs, vh = Screen.height / gs;

        switch (scr) {
            case Scr.Title:    DrawTitle(vw, vh); break;
            case Scr.Campaign: DrawCampaign(vw, vh); break;
            case Scr.Battle:   DrawBattleHud(vw, vh, gs); break;
            case Scr.Reward:   DrawReward(vw, vh); break;
            case Scr.End:      DrawEnd(vw, vh); break;
        }
        if (modalActive) DrawModal(vw, vh);

        // 沒被任何 GUI 控件吃掉的點擊 → 世界點擊
        var e = Event.current;
        if (scr == Scr.Battle && !modalActive && e.type == EventType.MouseDown && e.button == 0) {
            WorldClick();
            e.Use();
        }
    }

    void DrawTitle(float vw, float vh) {
        float cx = vw / 2;
        GUI.Label(new Rect(cx - 320, vh * 0.14f, 640, 70), "奪島遠征", stTitle);
        GUI.contentColor = new Color(0.62f, 0.68f, 0.82f);
        GUI.Label(new Rect(cx - 320, vh * 0.14f + 66, 640, 26), "I S L A N D   R A I D  ·  Unity 版 v2", stSub);
        GUI.Label(new Rect(cx - 280, vh * 0.32f, 560, 130),
            "逆轉 Bad North——這次換你登陸奪島。\n指揮小隊搶灘、攻佔據點、肅清守軍；\n每座島之後獲得新技能與援軍，一路打到最終要塞。\n小隊全滅即永久損失。\n\n點小隊(1-4鍵)選取 → 點灘頭登陸、點地面移動；Q 發動技能。", stSub);
        GUI.contentColor = Color.white;
        GUI.Label(new Rect(cx - 150, vh * 0.62f, 90, 30), "種子：", stSub);
        seedInput = GUI.TextField(new Rect(cx - 60, vh * 0.62f, 130, 30), seedInput, 12);
        if (GUI.Button(new Rect(cx - 90, vh * 0.72f, 180, 48), "出　征", stBtn)) {
            uint seed;
            if (!string.IsNullOrEmpty(seedInput)) {
                if (!uint.TryParse(seedInput, out seed)) {
                    seed = 7;
                    foreach (char ch in seedInput) unchecked { seed = seed * 31 + ch; }
                }
            } else seed = (uint)UnityEngine.Random.Range(1, int.MaxValue);
            NewRun(seed);
        }
    }

    void DrawCampaign(float vw, float vh) {
        GUI.Label(new Rect(0, 24, vw, 40), "遠征航線", stH2);
        GUI.contentColor = new Color(0.62f, 0.68f, 0.82f);
        GUI.Label(new Rect(0, 64, vw, 24),
            "種子 " + run.seed + " ・ 已攻陷 " + run.conquered + " 座島 ・ 選擇下一個目標", stSub);
        GUI.contentColor = Color.white;

        int nLayers = run.campaign.Count;
        float colW = Mathf.Min(110, (vw - 60) / nLayers);
        float x0 = (vw - colW * nLayers) / 2;
        for (int li = 0; li < nLayers; li++) {
            var layer = run.campaign[li];
            for (int ni = 0; ni < layer.Count; ni++) {
                var node = layer[ni];
                float bx = x0 + li * colW + 6;
                float by = vh * 0.42f - layer.Count * 52 + ni * 104;
                var r = new Rect(bx, by, colW - 12, 88);
                string stars = "";
                int sc = Mathf.Clamp(Mathf.CeilToInt(node.diff / 2f), 1, 4);
                for (int k = 0; k < sc; k++) stars += "★";
                string label = NodeMeta.Name(node.type) + "\n" + stars;
                if (node.cleared) {
                    GUI.enabled = false;
                    GUI.Button(r, label + "\n已佔領", stSmallBtn());
                    GUI.enabled = true;
                } else if (li == run.layer) {
                    GUI.backgroundColor = new Color(0.45f, 0.65f, 1f);
                    if (GUI.Button(r, label + "\n【進攻】", stSmallBtn())) StartBattle(node);
                    GUI.backgroundColor = Color.white;
                } else {
                    GUI.enabled = false;
                    GUI.Button(r, label, stSmallBtn());
                    GUI.enabled = true;
                }
            }
        }

        // 名冊
        var alive = run.roster;
        float rw = 170, rx = (vw - Mathf.Min(alive.Count, 4) * rw) / 2;
        for (int i = 0; i < alive.Count; i++) {
            var rs = alive[i];
            var r = new Rect(rx + (i % 4) * rw, vh * 0.74f + (i / 4) * 64, rw - 10, 58);
            string txt = "<b>" + RunState.Label(rs) + "</b>  " +
                (rs.alive ? RunState.MaxN(rs) + " 人" : "已全滅") +
                (rs.skill != null ? "\n技能：" + Skills.All[rs.skill].name : "\n" + Defs.Types[rs.type].desc);
            GUI.enabled = false;
            GUI.Button(r, txt, stChip);
            GUI.enabled = true;
        }
    }

    GUIStyle _smallBtn;
    GUIStyle stSmallBtn() {
        if (_smallBtn == null)
            _smallBtn = new GUIStyle(GUI.skin.button) { fontSize = 13, alignment = TextAnchor.MiddleCenter, wordWrap = true };
        return _smallBtn;
    }

    void DrawBattleHud(float vw, float vh, float gs) {
        if (battle == null) return;

        // 小隊晶片
        var ps = battle.squads.FindAll(s => s.side == Side.Player);
        for (int i = 0; i < ps.Count; i++) {
            var s = ps[i];
            var r = new Rect(8 + i * 128, 8, 122, 56);
            string st = s.dead ? "全滅" : (s.onBoat ? "船上 " : "") + s.soldiers.Count + " 人";
            string sk = s.skill != null ? "\n" + Skills.All[s.skill].name +
                (s.skillCd > 0 ? " " + Mathf.CeilToInt(s.skillCd) + "s" : " ✓") : "";
            string vetStars = "";
            for (int k = 0; k < s.vet; k++) vetStars += "★";
            GUI.backgroundColor = selected == s ? new Color(0.5f, 0.7f, 1f) : Color.white;
            GUI.enabled = !s.dead;
            if (GUI.Button(r, "<b>" + (i + 1) + " " + s.def.name + vetStars + "</b>\n" + st + sk, stChip)) {
                selected = s; targeting = false;
            }
            GUI.enabled = true;
            GUI.backgroundColor = Color.white;
        }

        // 目標欄
        int cap = 0;
        foreach (var h in battle.island.houses) if (h.captured) cap++;
        int foes = battle.squads.FindAll(s => s.side == Side.Enemy && !s.dead).Count;
        bool wavePending = battle.waves.Exists(w => !w.done);
        GUI.Box(new Rect(vw - 196, 8, 188, 66),
            "佔領據點  " + cap + " / " + battle.island.houses.Count +
            "\n殘餘守軍  " + foes + (wavePending ? "\n！敵援軍將至" : ""), stBox);

        // 技能鈕
        var selS = selected;
        if (selS != null && !selS.dead && selS.skill != null && !selS.onBoat) {
            var sk = Skills.All[selS.skill];
            string label = selS.skillCd > 0 ? sk.name + "  " + Mathf.CeilToInt(selS.skillCd) + "s"
                : targeting ? "點擊目標位置…" : sk.name + "（Q）";
            GUI.enabled = selS.skillCd <= 0;
            GUI.backgroundColor = targeting ? new Color(1f, 0.85f, 0.45f) : Color.white;
            if (GUI.Button(new Rect(vw / 2 - 110, vh - 62, 220, 46), label, stBtn)) SkillButtonPress();
            GUI.backgroundColor = Color.white;
            GUI.enabled = true;
        }

        // 訊息
        if (msgT > 0) {
            GUI.contentColor = msgColor;
            GUI.Label(new Rect(0, vh * 0.4f, vw, 44), msgText, stMsg);
            GUI.contentColor = Color.white;
        }

        // 佔領進度條 + 小隊人數標記（世界座標投影）
        var cm = view.cam;
        foreach (var h in battle.island.houses) {
            if (h.captured || h.progress <= 0) continue;
            var wp = View.W(h.tile.x + 0.5f, h.tile.y + 0.5f, h.tile.h * View.LIFT + 1.2f);
            var sp = cm.WorldToScreenPoint(wp);
            if (sp.z <= 0) continue;
            float gx = sp.x / gs, gy = (Screen.height - sp.y) / gs;
            GUI.color = new Color(0, 0, 0, 0.6f);
            GUI.DrawTexture(new Rect(gx - 26, gy - 5, 52, 9), Texture2D.whiteTexture);
            GUI.color = new Color(0.54f, 0.71f, 1f);
            GUI.DrawTexture(new Rect(gx - 25, gy - 4, 50 * h.progress, 7), Texture2D.whiteTexture);
            GUI.color = Color.white;
        }
        foreach (var s in battle.squads) {
            if (s.dead || s.onBoat) continue;
            var t0 = battle.island.At(s.x, s.y);
            float lift = (t0 != null ? t0.h : 0) * View.LIFT;
            var sp = cm.WorldToScreenPoint(View.W(s.x, s.y, lift + 0.75f));
            if (sp.z <= 0) continue;
            float gx = sp.x / gs, gy = (Screen.height - sp.y) / gs;
            GUI.color = new Color(0.05f, 0.08f, 0.16f, 0.75f);
            GUI.DrawTexture(new Rect(gx - 11, gy - 9, 22, 17), Texture2D.whiteTexture);
            GUI.color = s.side == Side.Player ? new Color(0.7f, 0.85f, 1f) : new Color(1f, 0.7f, 0.65f);
            GUI.Label(new Rect(gx - 14, gy - 10, 28, 18), s.soldiers.Count.ToString(), stBadge);
            GUI.color = Color.white;
        }
    }

    void DrawReward(float vw, float vh) {
        GUI.Label(new Rect(0, vh * 0.1f, vw, 44), "島嶼佔領", stH2);
        GUI.contentColor = new Color(0.62f, 0.68f, 0.82f);
        GUI.Label(new Rect(0, vh * 0.1f + 44, vw, 26), rewardSub, stSub);
        GUI.contentColor = Color.white;
        float cw = 200, ch = 210;
        float x0 = (vw - rewardCards.Count * (cw + 14)) / 2;
        for (int i = 0; i < rewardCards.Count; i++) {
            var c = rewardCards[i];
            var r = new Rect(x0 + i * (cw + 14), vh * 0.32f, cw, ch);
            string txt = "<b><size=17>" + c.title + "</size></b>\n\n" + c.desc + "\n\n<color=#f2c56b>" + c.tag + "</color>";
            if (GUI.Button(r, txt, stCard)) {
                var entry = c;
                ApplyCard(entry, () => {
                    rewardCards.Remove(entry);
                    picksLeft--;
                    if (picksLeft <= 0) scr = Scr.Campaign;
                    else rewardSub = "還可選擇 " + picksLeft + " 項";
                });
                break;
            }
        }
    }

    void DrawEnd(float vw, float vh) {
        GUI.contentColor = endWin ? new Color(0.95f, 0.77f, 0.42f) : new Color(0.94f, 0.48f, 0.43f);
        GUI.Label(new Rect(0, vh * 0.24f, vw, 50), endWin ? "要塞陷落・遠征成功" : "遠征覆滅", stH2);
        GUI.contentColor = new Color(0.62f, 0.68f, 0.82f);
        GUI.Label(new Rect(0, vh * 0.24f + 56, vw, 60),
            "攻陷島嶼 " + run.conquered + " 座 ・ 種子 " + run.seed + "\n" +
            (endWin ? "群島已是你的了，指揮官。" : "艦隊沉沒於怒濤之中——再組一支遠征軍吧。"), stSub);
        GUI.contentColor = Color.white;
        if (GUI.Button(new Rect(vw / 2 - 200, vh * 0.55f, 190, 46), "再次出征", stBtn))
            NewRun((uint)UnityEngine.Random.Range(1, int.MaxValue));
        if (GUI.Button(new Rect(vw / 2 + 10, vh * 0.55f, 190, 46), "同種子重來", stBtn))
            NewRun(run.seed);
    }

    void DrawModal(float vw, float vh) {
        GUI.color = new Color(0, 0, 0, 0.7f);
        GUI.DrawTexture(new Rect(0, 0, vw, vh), Texture2D.whiteTexture);
        GUI.color = Color.white;
        GUI.Label(new Rect(0, vh * 0.32f, vw, 36), modalTitle, stH2);
        float bw = 180;
        float x0 = (vw - modalList.Count * (bw + 12)) / 2;
        for (int i = 0; i < modalList.Count; i++) {
            var rs = modalList[i];
            var r = new Rect(x0 + i * (bw + 12), vh * 0.45f, bw, 52);
            if (GUI.Button(r, RunState.Label(rs) + "\n" + RunState.MaxN(rs) + " 人", stSmallBtn())) {
                modalActive = false;
                modalCb(rs);
                break;
            }
        }
    }
}

}
