class_name Rule
extends Resource
## 規則有兩種：
##   CHECK    — 審核檢查點（玩家該用來判斷人鬼的依據），逐晚解鎖
##   CONFLICT — 排房相沖規則（同層會出事），逐晚解鎖
## 兩種都資料驅動；判定邏輯在 Judge / RoomTable 依 check_id 分派。

enum Kind { CHECK, CONFLICT }
enum Severity { MINOR, MAJOR, RED }

@export var id: String = ""
@export var kind: Kind = Kind.CHECK
@export var check_id: String = ""               # 分派用：has_death_cert / id_cancelled / shadow / zodiac_clash / same_incident ...
@export var text_shown: String = ""             # 公告欄上寫給玩家看的字
@export var unlock_night: int = 1
@export var severity: Severity = Severity.MINOR
@export var is_true: bool = true                # 假規矩：交班簿寫的是錯的（v1 概念保留，MVP 全真）
@export var consequences: Array[Dictionary] = []  # [{kind: "chaos", value: 1}, {kind: "strike"}, {kind: "axis", target: "...", value: 10}]
@export var params: Dictionary = {}             # 規則專用參數


static func kind_from_string(s: String) -> Kind:
	return Kind.CONFLICT if s == "conflict" else Kind.CHECK


static func severity_from_string(s: String) -> Severity:
	match s:
		"major": return Severity.MAJOR
		"red": return Severity.RED
		_: return Severity.MINOR


static func from_dict(d: Dictionary) -> Rule:
	var r := Rule.new()
	r.id = d.get("id", "")
	r.kind = kind_from_string(d.get("kind", "check"))
	r.check_id = d.get("check_id", r.id)
	r.text_shown = d.get("text_shown", "")
	r.unlock_night = int(d.get("unlock_night", 1))
	r.severity = severity_from_string(d.get("severity", "minor"))
	r.is_true = d.get("is_true", true)
	r.consequences.assign(d.get("consequences", []))
	r.params = d.get("params", {})
	return r
