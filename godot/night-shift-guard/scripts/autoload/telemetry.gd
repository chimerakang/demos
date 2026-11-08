extends Node
## 遙測：記錄玩家每個決策，夜晚結束時打包送到後端。
## 沒設 endpoint 就只存本機（user://telemetry/），之後可從 Debug 面板匯出。

@export var endpoint: String = ""          # 例如 https://your-go-server/api/telemetry
@export var enabled: bool = true

var session_id: String = ""
var events: Array[Dictionary] = []
var _http: HTTPRequest


func _ready() -> void:
	session_id = "%d-%06d" % [Time.get_unix_time_from_system(), randi() % 1000000]
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	# 監聽所有玩家行為
	EventBus.stamp_pressed.connect(func(a, s): log_event("stamp", {"applicant": a, "stamp": s}))
	EventBus.question_asked.connect(func(a, q): log_event("question", {"applicant": a, "question": q}))
	EventBus.document_inspected.connect(func(a, d, s): log_event("inspect", {"applicant": a, "doc": d, "side": s}))
	EventBus.applicant_placed.connect(func(a, f, r): log_event("place", {"applicant": a, "floor": f, "room": r}))
	EventBus.applicant_removed.connect(func(a, f, r): log_event("unplace", {"applicant": a, "floor": f, "room": r}))
	EventBus.jiaobei_thrown.connect(func(rule, res): log_event("jiaobei", {"rule": rule, "result": res}))
	EventBus.applicant_resolved.connect(func(a, v): log_event("verdict", {"applicant": a.id, "truth": a.kind, "correct": v.get("correct", false), "reason": v.get("reason", "")}))
	EventBus.settlement_finished.connect(func(r): log_event("settlement", r))
	EventBus.night_ended.connect(_on_night_ended)
	EventBus.game_over.connect(func(reason): log_event("game_over", {"reason": reason}); flush())


func log_event(kind: String, payload: Dictionary) -> void:
	if not enabled:
		return
	events.append({
		"t": Time.get_ticks_msec(),
		"night": GameState.night,
		"gen": GameState.guard_generation,
		"kind": kind,
		"data": payload,
	})


func _on_night_ended(_night: int) -> void:
	flush()


func flush() -> void:
	if events.is_empty():
		return
	var packet := {
		"session": session_id,
		"platform": OS.get_name(),
		"version": ProjectSettings.get_setting("application/config/version", "dev"),
		"events": events.duplicate(),
	}
	events.clear()
	_save_local(packet)
	if endpoint != "":
		var body := JSON.stringify(packet)
		_http.request(endpoint, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)


func _save_local(packet: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute("user://telemetry")
	var path := "user://telemetry/%s-n%d.json" % [session_id, GameState.night]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(packet))


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code >= 300:
		push_warning("Telemetry 上傳失敗 result=%d code=%d" % [result, code])
