class_name Document
extends Resource
## 一份文件。fields 是玩家看得到的欄位；flaws 是系統知道的破綻。

enum Type { DEATH_CERT, HOUSEHOLD_REMOVAL, OBITUARY, ID_CARD, ALMANAC, OTHER }

@export var id: String = ""
@export var type: Type = Type.OTHER
@export var title: String = ""                  # 顯示用：死亡證明書 / 除戶謄本 / 訃聞 / 身分證
@export var fields: Dictionary = {}             # 欄位名 -> 值（全部字串，直接顯示）
@export var back_fields: Dictionary = {}        # 背面欄位（翻面才看得到）
@export var is_forged: bool = false
@export var flaws: Array[Dictionary] = []       # [{check: "seal_wrong", field: "醫院章", note: "章是殯儀館的"}]
@export var stamps: Array[String] = []          # 文件上有哪些章：cancelled / hospital / household_office ...


func has_flaw(check_id: String) -> bool:
	for f in flaws:
		if f.get("check", "") == check_id:
			return true
	return false


func field(name: String) -> String:
	return str(fields.get(name, back_fields.get(name, "")))


static func type_from_string(s: String) -> Type:
	match s:
		"death_cert": return Type.DEATH_CERT
		"household_removal": return Type.HOUSEHOLD_REMOVAL
		"obituary": return Type.OBITUARY
		"id_card": return Type.ID_CARD
		"almanac": return Type.ALMANAC
		_: return Type.OTHER


static func default_title(t: Type) -> String:
	match t:
		Type.DEATH_CERT: return "死亡證明書"
		Type.HOUSEHOLD_REMOVAL: return "除戶謄本"
		Type.OBITUARY: return "訃聞"
		Type.ID_CARD: return "國民身分證"
		Type.ALMANAC: return "農民曆"
		_: return "文件"


static func from_dict(d: Dictionary) -> Document:
	var doc := Document.new()
	doc.id = d.get("id", "")
	doc.type = type_from_string(d.get("type", "other"))
	doc.title = d.get("title", default_title(doc.type))
	doc.fields = d.get("fields", {})
	doc.back_fields = d.get("back_fields", {})
	doc.is_forged = d.get("is_forged", false)
	doc.flaws.assign(d.get("flaws", []))
	doc.stamps.assign(d.get("stamps", []))
	return doc
