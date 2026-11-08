# 資料格式說明

所有內容都在 `data/*.json`，改資料不用改程式。載入由 `scripts/autoload/data_loader.gd` 負責，載入錯誤會在 Godot 輸出面板顯示警告。

## applicants.json — 登記者池

一個陣列，每筆是一位登記者。

| 欄位 | 型別 | 說明 |
|---|---|---|
| `id` | string | 唯一 id，`nights.json` 用它排隊 |
| `name` | string | 文件上的名字 |
| `kind` | `ghost` / `human` / `human_disguised` / `inspector` | 真相。鬼 → 該放行；活人與假冒 → 該拒絕；抽查員 → 該放行 |
| `is_story` | bool | 故事鬼：有執念軸，第一次出現時用 `initial_axis` |
| `initial_axis` | int | −100..100 |
| `zodiac` | string | 鼠牛虎兔龍蛇馬羊猴雞狗豬，排房生肖相沖用 |
| `death_date` / `death_place` | string | 同日同地 = 同一事故（`same_incident` 規則） |
| `address` | string | 除戶謄本同地址不同年代 = 前後任屋主 |
| `documents[]` | Document | 見下 |
| `portrait` | object | 半身像部件 id：`face` `hair` `outfit` `trait`（美術階段對應到 sprite） |
| `has_shadow` / `feet_on_ground` | bool | 活人才 true；第 3 晚解鎖後畫面會顯示 |
| `visual_tells[]` | string | 其他畫面破綻 tag。`Judge.check_fires` 遇到未知 `check_id` 時會查這裡，方便先用資料實驗新檢查點 |
| `answers` | object | `question_id → {text, contradicts[]}`；`contradicts` 非空代表答案跟文件矛盾（第 4 晚檢查點） |
| `relations[]` | object | `{with, kind, clue}`，kind：`hostile` `family` `debt` `property` `zodiac`。這是排房推理的**真相**，玩家要從文件推出來；`clue` 是事件發生時顯示的文字 |
| `intro_line` / `plea_line` | string | 走到櫃檯第一句 / 被拒絕時說的話 |
| `return_as` | string | 活人被放進來後，隔晚以這個 id 的鬼回來 |

## Document（documents[] 的元素）

| 欄位 | 說明 |
|---|---|
| `id` | 唯一 |
| `type` | `death_cert` 死亡證明 / `household_removal` 除戶謄本 / `obituary` 訃聞 / `id_card` 身分證 / `almanac` 農民曆 / `other` |
| `title` | 可省略，依 type 給預設中文 |
| `fields` / `back_fields` | 正面 / 背面欄位，全部字串，直接顯示 |
| `stamps[]` | 文件上的章：`cancelled` 註銷、`hospital` 醫院、`household_office` 戶政、`prosecutor` 地檢署、`funeral_home` 殯葬業、`committee` 管委會 |
| `is_forged` | 第 6 晚 `forged_document` 檢查點用 |
| `flaws[]` | `{check, field, note}`，系統知道的破綻；`check` 可被 `Judge` 以 `has_flaw()` 查 |

## rules.json — 規則

| 欄位 | 說明 |
|---|---|
| `kind` | `check` 審核檢查點 / `conflict` 排房相沖 |
| `check_id` | 分派鍵。CHECK 在 `Judge.check_fires` 處理；CONFLICT 在 `RoomTable.conflict_fires` 處理。新規則 = JSON 一筆 + 對應函式一個 match 分支 |
| `text_shown` | 公告欄文字 |
| `unlock_night` | 第幾晚起生效 |
| `severity` | `minor` / `major` / `red` |
| `consequences[]` | 相沖事件的後果：`{kind: chaos|strike|pay|axis|damage_floor|flag, value, target}`；`axis` 的 `target` 可用 `a` / `b` 指事件雙方 |

目前已實作的 `check_id`：
- CHECK：`has_death_cert` `id_cancelled` `shadow` `feet` `answer_contradiction` `almanac_clash` `forged_document` `removal_date_future`
- CONFLICT：`same_incident` `zodiac_clash` `family_same_floor` `debt` `property`，以及任何與 `relations[].kind` 同名的泛用鍵

## nights.json — 七晚時程

| 欄位 | 說明 |
|---|---|
| `night` | 1..7 |
| `title` / `notice` | 開班畫面 |
| `applicants[]` | 今晚排隊的 id，依序；上一晚被放進來的活人會自動加到隊尾（`return_as`） |
| `shuffle` | 是否打亂順序 |
| `jiaobei_uses` | 擲筊次數（尚未實作 UI） |

## questions.json

`question_id → {text}`。登記者的 `answers` 只需要包含牠會回答的那些問題。
