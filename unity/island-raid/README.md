# 奪島遠征 Island Raid v2 — Unity 版

JS 原型（`/island-raid/`）的 Unity 3D 移植：方塊小島、球體士兵、同一套
roguelike 奪島玩法（同種子＝同戰役）。透過 GitHub Actions（GameCI）自動
編譯 WebGL 並發佈到 **`/island-raid-v2/`**。

## 一次性設定（讓 CI 能編譯）

Unity 編譯需要 license，請在 repo **Settings → Secrets and variables →
Actions** 加入：

| Secret | 內容 |
|---|---|
| `UNITY_EMAIL` | Unity 帳號 email |
| `UNITY_PASSWORD` | Unity 帳號密碼 |
| `UNITY_LICENSE` | 個人版 license（`.ulf` 檔的完整文字內容） |

取得 `.ulf`：照 [GameCI Activation 文件](https://game.ci/docs/github/activation)
跑一次 activation 流程（或在本機裝好 Unity 後，從
`C:\ProgramData\Unity\Unity_lic.ulf` / `~/Library/Application Support/Unity/Unity_lic.ulf`
複製內容）。

設定完成後：**Actions → unity-webgl-island-raid-v2 → Run workflow**，
或推送任何 `unity/island-raid/` 底下的變更即可觸發。建置產物會自動
commit 到 `island-raid-v2/`，GitHub Pages 直接可玩。

## 本機開發

1. Unity Hub 安裝 **6000.0.34f1**（其他 6000.x 也可，改
   `ProjectSettings/ProjectVersion.txt` 即可）
2. 開啟本專案資料夾，隨便開一個空場景按 **Play**——
   `Bootstrap`（RuntimeInitializeOnLoadMethod）會自動建立相機、光源、
   材質與整個遊戲，不需要手動擺場景。

## 結構

```
Assets/Scripts/Core.cs    RNG／兵種／技能／戰役狀態（與 JS 版同款 mulberry32）
Assets/Scripts/Island.cs  島嶼程序生成 + BFS 尋路
Assets/Scripts/Sim.cs     戰鬥模擬：小隊、士兵個體、箭矢、佔領、守軍 AI
Assets/Scripts/View.cs    3D 視覺層（方塊地形、士兵、船、特效、材質庫）
Assets/Scripts/Game.cs    畫面狀態機、IMGUI 介面、輸入、獎勵流程
Assets/Editor/BuildScript.cs  CI 建置進入點（生成場景/材質、gzip WebGL）
Assets/Resources/NotoSansTC.otf  中文字型子集（OFL，僅含使用到的字）
```

備註：WebGL 用 gzip + decompression fallback，GitHub Pages 不需任何
header 設定即可載入。
