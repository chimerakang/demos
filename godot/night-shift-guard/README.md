# 夜班保全 — Night Shift Guard

> 對人兇，對鬼客氣。只有死人才能入住，而且仇家不能同層。

Papers, Please 式櫃檯審核 × 房間配置推理。福德宮香客大樓是陰間入口的前站，你是夜班櫃檯：判斷來登記的是人是鬼，只讓鬼住進來，還要從文件推出誰跟誰有仇，別排在同一層。

**狀態**：MVP 灰盒骨架。設計文件見 Claude 專案《夜班保全》的 `MVP與工作項目-v2-審核排房版`。

## 技術

- Godot **4.7**，Compatibility 渲染器（WebGL 2.0），960×540 整數縮放
- 網頁匯出：**單執行緒**（不需要 COOP/COEP 標頭，任何靜態主機可放）
- 全部內容資料驅動：`data/*.json`，格式見 `data/schema/README.md`
- 遙測：每個決策記錄到 `user://telemetry/`，設定 `Telemetry.endpoint` 後會 POST 到後端

## 結構

```
project.godot            Compatibility / 960×540 / autoloads
export_presets.cfg       Web preset（單執行緒）
scenes/
  main.tscn              入口
  desk/desk_greybox.gd   灰盒櫃檯 UI（程式建，零美術）
scripts/
  autoload/
    event_bus.gd         所有事件
    game_state.gd        進度、軸、混亂、記點、房間表、筆記本、存檔
    data_loader.gd       JSON → Resource
    telemetry.gd         決策記錄
  data/
    applicant.gd         登記者
    document.gd          文件
    rule.gd              檢查點 / 相沖規則
  core/
    judge.gd             審核判定（蓋章對不對、漏了哪些線索）
    room_table.gd        排房相沖掃描
    night_controller.gd  一晚的狀態機與後果套用
data/
  applicants.json        登記者池（已有第 1–3 晚的 19 位）
  rules.json             12 條規則，逐晚解鎖
  nights.json            七晚時程（第 4–6 晚待填）
  questions.json         對講機問句
tools/
  subset_font.sh         中文字型子集（網頁版必做）
  export_web.sh          匯出 + 本機預覽
```

## 開始

```bash
# 1. 用 Godot 4.7 開啟 project.godot，直接 F5 可跑灰盒（中文會是方框，先裝字型）
# 2. 字型：下載 Noto Sans TC Regular 到 assets/fonts/，然後
pip install fonttools brotli
./tools/subset_font.sh
#    再到 project.godot 取消 gui/theme/custom_font 的註解
# 3. 網頁匯出
./tools/export_web.sh            # → build/web，開 http://localhost:8060
```

## 灰盒操作

- 左欄：登記者、第一句話、文件（點開看欄位與章）
- 中欄：問句（問過會變灰）、三個章：准予入住 **A** / 拒絕 **D** / 通報 **R**
- 右欄：房間表 3×3，先點一格再蓋「准予入住」；點已入住的格可清空
- 下方：事件 log，錯誤判定會列出「可用線索」（玩家本來能抓到的檢查點）

## 新增內容的方式

- 新登記者：`applicants.json` 加一筆，`nights.json` 排進某晚
- 新檢查點：`rules.json` 加一筆 `kind: check`，`judge.gd` 的 `check_fires()` 加一個分支（或先用 `visual_tells` tag 實驗，不用動程式）
- 新相沖規則：`rules.json` 加一筆 `kind: conflict`，`room_table.gd` 的 `conflict_fires()` 加分支（或用 `relations[].kind` 同名泛用鍵）

## 待做（對應 WBS）

- [ ] 擲筊 UI 與假規矩驗證
- [ ] 農民曆文件與 `almanac_clash` 的日期邏輯
- [ ] 第 4–6 晚登記者與公告
- [ ] 半身像部件系統（目前 portrait 只是 id）
- [ ] 正式 desk 場景（拖曳文件、並排比對、印章動畫）
- [ ] Debug 面板：跳晚、強制抽人、改狀態
- [ ] 三結局演出
