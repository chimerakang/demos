class_name RoomTable
extends RefCounted
## 排房相沖檢查。結算時掃每一層，兩兩比對住戶。
## 回傳事件列表：[{floor, a, b, rule_id, kind, text, consequences[]}]

const ZODIAC_CLASH := {
	"鼠": "馬", "馬": "鼠",
	"牛": "羊", "羊": "牛",
	"虎": "猴", "猴": "虎",
	"兔": "雞", "雞": "兔",
	"龍": "狗", "狗": "龍",
	"蛇": "豬", "豬": "蛇",
}


static func settle(active_rules: Array[Rule]) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for f in GameState.FLOORS:
		var occupants := GameState.occupants_of_floor(f)
		for i in occupants.size():
			for j in range(i + 1, occupants.size()):
				var a := occupants[i]
				var b := occupants[j]
				for r in active_rules:
					if r.kind != Rule.Kind.CONFLICT:
						continue
					var hit := conflict_fires(r, a, b)
					if hit.is_empty():
						continue
					events.append({
						"floor": f,
						"a": a.id,
						"b": b.id,
						"rule_id": r.id,
						"kind": hit.get("kind", "hostile"),
						"text": hit.get("text", r.text_shown),
						"consequences": r.consequences,
					})
					# 事件發生 → 關係自動寫進筆記本（繼承）
					GameState.note_relation(a.id, b.id, hit.get("kind", "hostile"))
	return events


## 單一相沖規則對一對住戶是否成立。空 Dictionary = 不成立。
## 新增規則：在這裡加分支 + rules.json 一筆。
static func conflict_fires(r: Rule, a: Applicant, b: Applicant) -> Dictionary:
	match r.check_id:
		"zodiac_clash":
			if a.zodiac != "" and ZODIAC_CLASH.get(a.zodiac, "") == b.zodiac:
				return {"kind": "zodiac", "text": "%s（%s）與 %s（%s）生肖相沖" % [a.display_name, a.zodiac, b.display_name, b.zodiac]}
		"same_incident":
			if a.death_date != "" and a.death_date == b.death_date and a.death_place == b.death_place:
				var rel := _relation_between(a, b)
				if rel.get("kind", "") == "hostile":
					return {"kind": "hostile", "text": rel.get("clue", "同一場事故的兩人在同一層")}
		"family_same_floor":
			# 家人同層：正向事件（推安息），不是衝突，但也回報讓結算處理
			var rel := _relation_between(a, b)
			if rel.get("kind", "") == "family":
				return {"kind": "family", "text": rel.get("clue", "家人終於在同一層")}
		"debt":
			var rel := _relation_between(a, b)
			if rel.get("kind", "") == "debt":
				return {"kind": "debt", "text": rel.get("clue", "債主與欠債者同層")}
		"property":
			var rel := _relation_between(a, b)
			if rel.get("kind", "") == "property":
				return {"kind": "property", "text": rel.get("clue", "前後任屋主同層")}
		_:
			# 泛用：relations 裡 kind 與 check_id 同名
			var rel := _relation_between(a, b)
			if rel.get("kind", "") == r.check_id:
				return {"kind": r.check_id, "text": rel.get("clue", r.text_shown)}
	return {}


## 關係只需在 JSON 的其中一方宣告；這裡雙向查。
static func _relation_between(a: Applicant, b: Applicant) -> Dictionary:
	var rel := a.relation_with(b.id)
	if rel.is_empty():
		rel = b.relation_with(a.id)
	return rel
