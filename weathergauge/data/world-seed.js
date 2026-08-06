// 由 world-seed.json 生成（canonical 為 .json）
const WORLD = {
  "meta": {
    "name": "琉璃海（架空群島・種子資料 v0.1）",
    "spec": "docs/research/TRADE-DATA-SPEC.md",
    "mapSize": [1000, 600]
  },
  "factions": [
    {
      "id": "fa_zhuyuan",
      "name": "朱鳶商會",
      "color": "#a13527",
      "navalShare": 0.35,
      "doctrineBias": "assault",
      "blurb": "南琉璃海的香料壟斷者，艦隊寧沉不讓。",
      "repEffects": { "20": "港口通行", "50": "護航合約", "80": "聯合艦隊" }
    },
    {
      "id": "fa_xuanchao",
      "name": "玄潮同盟",
      "color": "#31506b",
      "navalShare": 0.45,
      "doctrineBias": "harass",
      "blurb": "北海船木與鐵器的行會聯盟，信奉「不沉的船才賺錢」。",
      "repEffects": { "20": "港口通行", "50": "劫掠情報", "80": "私掠許可" }
    },
    {
      "id": "fa_baifan",
      "name": "白帆自由港",
      "color": "#c9a227",
      "navalShare": 0.25,
      "doctrineBias": "boarding",
      "blurb": "不問旗幟的中立港聯合，接舷奪船的老手，什麼都買、什麼都賣。",
      "repEffects": { "20": "黑市造船", "50": "走私航線", "80": "傭兵艦隊" }
    }
  ],
  "ports": [
    { "id": "port_liuli", "name": "琉璃港", "pos": [280, 470], "faction": "fa_zhuyuan", "scale": 5, "tags": ["spice", "capital"] },
    { "id": "port_zhuyuanbo", "name": "朱鳶泊", "pos": [520, 500], "faction": "fa_zhuyuan", "scale": 3, "tags": ["spice"] },
    { "id": "port_hanya", "name": "寒鴉城", "pos": [300, 110], "faction": "fa_xuanchao", "scale": 5, "tags": ["timber", "capital"] },
    { "id": "port_tiezhen", "name": "鐵砧嶼", "pos": [560, 90], "faction": "fa_xuanchao", "scale": 3, "tags": ["naval"] },
    { "id": "port_baifangang", "name": "白帆港", "pos": [700, 300], "faction": "fa_baifan", "scale": 4, "tags": ["freeport"] },
    { "id": "port_wuyu", "name": "霧嶼", "pos": [880, 180], "faction": "fa_baifan", "scale": 2, "tags": ["smuggle"] },
    { "id": "port_fengkousai", "name": "風口砦", "pos": [450, 300], "faction": "neutral", "scale": 2, "tags": ["fort", "chokepoint"] },
    { "id": "port_yueya", "name": "月牙灣", "pos": [120, 280], "faction": "neutral", "scale": 3, "tags": ["pearl"] }
  ],
  "chokes": [
    { "id": "choke_fengkou", "name": "風口海峽", "pos": [450, 300], "blurb": "南北琉璃海唯一深水道，風帶交界，誰的炮台指著海峽，誰就對過路的每一分流量收稅。" }
  ],
  "routes": [
    { "id": "r_liuli_zhuyuanbo", "ports": ["port_liuli", "port_zhuyuanbo"], "baseFlow": 60, "wind": 1, "choke": null, "risk": 1 },
    { "id": "r_liuli_fengkou", "ports": ["port_liuli", "port_fengkousai"], "baseFlow": 80, "wind": 0, "choke": "choke_fengkou", "risk": 2 },
    { "id": "r_fengkou_hanya", "ports": ["port_fengkousai", "port_hanya"], "baseFlow": 80, "wind": -1, "choke": "choke_fengkou", "risk": 2 },
    { "id": "r_hanya_tiezhen", "ports": ["port_hanya", "port_tiezhen"], "baseFlow": 55, "wind": 1, "choke": null, "risk": 1 },
    { "id": "r_tiezhen_wuyu", "ports": ["port_tiezhen", "port_wuyu"], "baseFlow": 30, "wind": 0, "choke": null, "risk": 2 },
    { "id": "r_wuyu_baifangang", "ports": ["port_wuyu", "port_baifangang"], "baseFlow": 40, "wind": 1, "choke": null, "risk": 3 },
    { "id": "r_baifangang_zhuyuanbo", "ports": ["port_baifangang", "port_zhuyuanbo"], "baseFlow": 70, "wind": 0, "choke": null, "risk": 2 },
    { "id": "r_baifangang_fengkou", "ports": ["port_baifangang", "port_fengkousai"], "baseFlow": 50, "wind": -1, "choke": "choke_fengkou", "risk": 1 },
    { "id": "r_liuli_yueya", "ports": ["port_liuli", "port_yueya"], "baseFlow": 45, "wind": 0, "choke": null, "risk": 1 },
    { "id": "r_yueya_hanya", "ports": ["port_yueya", "port_hanya"], "baseFlow": 45, "wind": -1, "choke": null, "risk": 2 },
    { "id": "r_zhuyuanbo_tiezhen", "ports": ["port_zhuyuanbo", "port_tiezhen"], "baseFlow": 35, "wind": 0, "choke": null, "risk": 3 },
    { "id": "r_hanya_baifangang", "ports": ["port_hanya", "port_baifangang"], "baseFlow": 50, "wind": 1, "choke": null, "risk": 2 }
  ],
  "shipClasses": [
    { "id": "frigate", "name": "巡防艦", "hull": 80, "sail": 110, "crew": 90, "speed": 4.2, "turn": 0.45, "guns": 0.8, "command": 1, "upkeep": 8 },
    { "id": "shipOfLine", "name": "戰列艦", "hull": 140, "sail": 90, "crew": 120, "speed": 2.8, "turn": 0.22, "guns": 1.5, "command": 3, "upkeep": 20 },
    { "id": "fireship", "name": "縱火船", "hull": 45, "sail": 100, "crew": 30, "speed": 3.8, "turn": 0.5, "guns": 0.2, "command": 1, "upkeep": 4, "oneUse": true },
    { "id": "boarder", "name": "接舷船", "hull": 90, "sail": 100, "crew": 150, "speed": 3.4, "turn": 0.38, "guns": 0.6, "command": 2, "upkeep": 12 }
  ],
  "captains": [
    {
      "id": "cap_yanling", "name": "雁翎", "faction": "fa_zhuyuan",
      "passive": "rule_slot_plus_one", "active": "forced_turn",
      "hireCost": 300, "wage": 15,
      "lines": { "recruit": "商會欠我三條船，你出得起第四條嗎？", "victory": "記帳：修帆費從戰利品裡扣。", "sunk": "……又欠一條。" }
    },
    {
      "id": "cap_moxue", "name": "墨雪", "faction": "fa_xuanchao",
      "passive": "chain_shot_bonus", "active": "full_reload",
      "hireCost": 280, "wage": 14,
      "lines": { "recruit": "剪了帆，海就是牢房。", "victory": "一艘都沒沉——這才叫贏。", "sunk": "撈人優先，船再造就有。" }
    },
    {
      "id": "cap_tiaogang", "name": "跳幫虎", "faction": "fa_baifan",
      "passive": "grape_shot_bonus", "active": "boarding_rush",
      "hireCost": 350, "wage": 18,
      "lines": { "recruit": "沉船是浪費，我只收整船。", "victory": "看，多了一艘。", "sunk": "呸——下次搶艘更大的。" }
    }
  ],
  "contractTemplates": [
    { "type": "escort", "name": "護航", "desc": "商船隊過 {route}，保它抵港", "rewardBase": 120, "repDelta": 8, "forcedBattle": true },
    { "type": "raid", "name": "劫掠", "desc": "打斷 {faction} 在 {route} 的流量", "rewardBase": 150, "repDelta": -12, "forcedBattle": true },
    { "type": "blockade", "name": "封鎖", "desc": "堵住 {port} 三回合", "rewardBase": 250, "repDelta": -20, "forcedBattle": true },
    { "type": "privateer", "name": "私掠許可", "desc": "持 {faction} 許可，劫掠其敵對商道，戰利品三七分", "rewardBase": 0, "repDelta": 15, "forcedBattle": true, "comeback": true }
  ]
};
