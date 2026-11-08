class_name NightController
extends Node
## 一晚的狀態機。
## OPEN → QUEUE(登記者逐一) → SETTLE → DAY → (下一晚 或 結局)
## 只管流程與後果套用；畫面由 desk 場景監聽 EventBus 更新。

enum State { IDLE, OPEN, QUEUE, SETTLE, DAY, ENDED }

var state: State = State.IDLE
var queue: Array[Applicant] = []
var current: Applicant = null
var active_rules: Array[Rule] = []
var pending_returns: Array[String] = []     # 活人被放進來 → 隔晚回來的 applicant id


func start_night() -> void:
	var cfg := DataLoader.night_config(GameState.night)
	if cfg.is_empty():
		push_error("nights.json 沒有第 %d 晚" % GameState.night)
		return
	GameState.begin_night()
	active_rules = DataLoader.rules_active_on(GameState.night)
	_build_queue(cfg)
	state = State.OPEN
	# 開班公告由畫面顯示；按下開始後進 QUEUE


func open_desk() -> void:
	state = State.QUEUE
	next_applicant()


func next_applicant() -> void:
	if queue.is_empty():
		current = null
		EventBus.queue_empty.emit()
		settle()
		return
	current = queue.pop_front()
	EventBus.applicant_arrived.emit(current)


## 玩家蓋章。approve 時需先排房（由畫面保證），這裡只判定。
func stamp(stamp_id: String) -> void:
	if state != State.QUEUE or current == null:
		return
	EventBus.stamp_pressed.emit(current.id, stamp_id)
	var verdict := Judge.evaluate(current, stamp_id, active_rules)
	_apply_consequences(verdict["consequences"])
	if verdict["correct"]:
		GameState.correct_count += 1
	else:
		GameState.wrong_count += 1
	GameState.notes["applicants_seen"][current.id] = "ghost" if current.is_ghost() else "human"
	EventBus.applicant_resolved.emit(current, verdict)
	# 若已被記滿點，game_over 會從 GameState 發出，這裡不再往下走
	if GameState.strikes >= GameState.MAX_STRIKES:
		state = State.ENDED
		return
	next_applicant()


func settle() -> void:
	state = State.SETTLE
	EventBus.settlement_started.emit()
	var events := RoomTable.settle(active_rules)
	for ev in events:
		_apply_consequences(ev["consequences"], ev)
	# 故事鬼：讓牠等太久、沒排房 → 軸 +5
	for id in GameState.axis.keys():
		if GameState.find_room(id) == Vector2i(-1, -1) and GameState.residents.has(id):
			GameState.push_axis(id, 5)
	var report := {
		"night": GameState.night,
		"correct": GameState.correct_count,
		"wrong": GameState.wrong_count,
		"pay": GameState.tonight_pay,
		"chaos": GameState.chaos,
		"strikes": GameState.strikes,
		"events": events,
		"axis": GameState.axis.duplicate(),
	}
	EventBus.settlement_finished.emit(report)
	state = State.DAY


func end_day() -> void:
	GameState.end_night()
	if GameState.night > GameState.MAX_NIGHTS:
		state = State.ENDED
		EventBus.game_over.emit(_ending())
	else:
		state = State.IDLE


## 死亡後重來：天數不變，換下一任
func replace_guard_and_restart() -> void:
	GameState.replace_guard()
	start_night()


# ── 內部 ──

func _build_queue(cfg: Dictionary) -> void:
	queue.clear()
	var ids: Array = cfg.get("applicants", [])
	# 上一晚被放進來的活人，今晚以鬼的身分回來
	for rid in pending_returns:
		ids.append(rid)
	pending_returns.clear()
	for id in ids:
		var a := DataLoader.get_applicant(id)
		if a == null:
			push_warning("nights.json 引用了不存在的 applicant: " + str(id))
			continue
		if a.is_story and not GameState.axis.has(a.id):
			GameState.axis[a.id] = a.initial_axis
		queue.append(a)
	if cfg.get("shuffle", false):
		queue.shuffle()


func _apply_consequences(list: Array, context: Dictionary = {}) -> void:
	for c in list:
		match c.get("kind", ""):
			"pay":
				GameState.add_pay(int(c.get("value", 0)))
			"strike":
				GameState.add_strike(c.get("reason", ""))
			"chaos":
				GameState.add_chaos(int(c.get("value", 1)))
			"axis":
				var target: String = c.get("target", "")
				if target == "a" or target == "b":
					target = context.get(target, "")
				if target != "":
					GameState.push_axis(target, int(c.get("value", 0)))
			"damage_floor":
				var f := int(context.get("floor", c.get("floor", -1)))
				if f >= 0 and not GameState.damaged_floors.has(f):
					GameState.damaged_floors.append(f)
			"human_admitted":
				var ret: String = c.get("return_as", "")
				if ret != "":
					pending_returns.append(ret)
			"flag":
				GameState.flags[c.get("key", "")] = c.get("value", true)
			_:
				pass


func _ending() -> String:
	var all_rest := true
	var fallen := 0
	for id in GameState.axis.keys():
		var v: int = GameState.axis[id]
		if v > -80:
			all_rest = false
		if v >= 80:
			fallen += 1
	if all_rest and GameState.chaos <= 3:
		return "ending_cleared"
	if fallen >= 2 or GameState.chaos >= 8:
		return "ending_fallen"
	return "ending_balance"
