extends Node
## 全域遊戲狀態。只存資料，不含流程邏輯。
## 存檔到 user://save.json（網頁版映射到 IndexedDB）。

const SAVE_PATH := "user://save.json"
const MAX_NIGHTS := 7
const MAX_STRIKES := 3
const FLOORS := 3
const ROOMS_PER_FLOOR := 3

# ── 進度 ──
var night: int = 1
var guard_generation: int = 1          # 第幾任保全（死亡後 +1）
var debt: int = 300000
var pay_per_correct: int = 1500

# ── 本晚 ──
var strikes: int = 0
var chaos: int = 0                     # 0..10
var tonight_pay: int = 0
var correct_count: int = 0
var wrong_count: int = 0

# ── 住戶 ──
var axis: Dictionary = {}              # resident_id -> int (-100..100)，只給故事鬼
var rooms: Array = []                  # rooms[floor][room] = applicant_id 或 ""
var residents: Dictionary = {}         # applicant_id -> Applicant（已入住）
var damaged_floors: Array[int] = []

# ── 筆記本（跨保全繼承）──
var notes: Dictionary = {
	"relations": {},                   # "idA|idB" -> "hostile" / "family" / "debt"
	"rules_verified": {},              # rule_id -> true/false
	"applicants_seen": {},             # applicant_id -> "ghost" / "human"
}

# ── 旗標與計數 ──
var flags: Dictionary = {}
var counters: Dictionary = {}


func _ready() -> void:
	_reset_rooms()


func _reset_rooms() -> void:
	rooms.clear()
	for f in FLOORS:
		var row: Array = []
		for r in ROOMS_PER_FLOOR:
			row.append("")
		rooms.append(row)


# ── 軸 / 混亂 / 記點 ──

func set_axis(resident_id: String, value: int) -> void:
	var old: int = axis.get(resident_id, 0)
	var new_value: int = clampi(value, -100, 100)
	axis[resident_id] = new_value
	if old != new_value:
		EventBus.axis_changed.emit(resident_id, old, new_value)


func push_axis(resident_id: String, delta: int) -> void:
	set_axis(resident_id, axis.get(resident_id, 0) + delta)


func add_chaos(delta: int) -> void:
	var old := chaos
	chaos = clampi(chaos + delta, 0, 10)
	if old != chaos:
		EventBus.chaos_changed.emit(old, chaos)


func add_strike(reason: String) -> void:
	strikes += 1
	EventBus.strike_added.emit(strikes, reason)
	if strikes >= MAX_STRIKES:
		EventBus.game_over.emit("strikes")


func add_pay(amount: int) -> void:
	tonight_pay += amount
	EventBus.pay_changed.emit(tonight_pay)


# ── 房間 ──

func place(applicant: Applicant, floor: int, room: int) -> bool:
	if rooms[floor][room] != "":
		return false
	rooms[floor][room] = applicant.id
	residents[applicant.id] = applicant
	EventBus.applicant_placed.emit(applicant.id, floor, room)
	return true


func remove_from_room(floor: int, room: int) -> void:
	var id: String = rooms[floor][room]
	if id == "":
		return
	rooms[floor][room] = ""
	EventBus.applicant_removed.emit(id, floor, room)


func occupants_of_floor(floor: int) -> Array[Applicant]:
	var out: Array[Applicant] = []
	for id in rooms[floor]:
		if id != "" and residents.has(id):
			out.append(residents[id])
	return out


## 某層第一個空房的 index，沒有則 -1
func find_free_slot_for_test(floor: int) -> int:
	for r in ROOMS_PER_FLOOR:
		if rooms[floor][r] == "":
			return r
	return -1


func find_room(applicant_id: String) -> Vector2i:
	for f in FLOORS:
		for r in ROOMS_PER_FLOOR:
			if rooms[f][r] == applicant_id:
				return Vector2i(f, r)
	return Vector2i(-1, -1)


# ── 筆記本 ──

func note_relation(id_a: String, id_b: String, kind: String) -> void:
	var key := _pair_key(id_a, id_b)
	notes["relations"][key] = kind
	EventBus.note_updated.emit("relation:" + key, kind)


func known_relation(id_a: String, id_b: String) -> String:
	return notes["relations"].get(_pair_key(id_a, id_b), "")


func _pair_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


# ── 夜晚切換 ──

func begin_night() -> void:
	strikes = 0
	tonight_pay = 0
	correct_count = 0
	wrong_count = 0
	EventBus.night_started.emit(night)


func end_night() -> void:
	debt = maxi(debt - tonight_pay, 0)
	EventBus.night_ended.emit(night)
	night += 1
	save()


## 死亡：換下一任保全。筆記本、軸、混亂、房間保留；天數不重置。
func replace_guard() -> void:
	guard_generation += 1
	strikes = 0
	save()


# ── 存檔 ──

func save() -> void:
	var data := {
		"night": night,
		"guard_generation": guard_generation,
		"debt": debt,
		"chaos": chaos,
		"axis": axis,
		"rooms": rooms,
		"resident_ids": residents.keys(),
		"damaged_floors": damaged_floors,
		"notes": notes,
		"flags": flags,
		"counters": counters,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))


func load_save() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	night = int(parsed.get("night", 1))
	guard_generation = int(parsed.get("guard_generation", 1))
	debt = int(parsed.get("debt", debt))
	chaos = int(parsed.get("chaos", 0))
	axis = parsed.get("axis", {})
	rooms = parsed.get("rooms", [])
	if rooms.is_empty():
		_reset_rooms()
	damaged_floors.assign(parsed.get("damaged_floors", []))
	notes = parsed.get("notes", notes)
	flags = parsed.get("flags", {})
	counters = parsed.get("counters", {})
	residents.clear()
	for id in parsed.get("resident_ids", []):
		var a := DataLoader.get_applicant(id)
		if a:
			residents[id] = a
	return true


func reset_all() -> void:
	night = 1
	guard_generation = 1
	debt = 300000
	chaos = 0
	axis.clear()
	residents.clear()
	damaged_floors.clear()
	notes = {"relations": {}, "rules_verified": {}, "applicants_seen": {}}
	flags.clear()
	counters.clear()
	_reset_rooms()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
