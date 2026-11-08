extends Node
## 從 res://data/*.json 載入所有內容資料，轉成 Resource。
## 內容全部資料驅動：改 JSON 不用改程式。

const APPLICANTS_PATH := "res://data/applicants.json"
const RULES_PATH := "res://data/rules.json"
const NIGHTS_PATH := "res://data/nights.json"
const QUESTIONS_PATH := "res://data/questions.json"

var applicants: Dictionary = {}     # id -> Applicant
var rules: Array[Rule] = []
var nights: Array = []              # nights.json 的陣列，index = night-1
var questions: Dictionary = {}      # question_id -> {text}
var load_errors: Array[String] = []


func _ready() -> void:
	reload()


func reload() -> void:
	applicants.clear()
	rules.clear()
	nights.clear()
	questions.clear()
	load_errors.clear()
	_load_applicants()
	_load_rules()
	_load_nights()
	_load_questions()
	if not load_errors.is_empty():
		push_warning("DataLoader: %d 個載入錯誤" % load_errors.size())
		for e in load_errors:
			push_warning("  " + e)


func get_applicant(id: String) -> Applicant:
	return applicants.get(id)


func night_config(night: int) -> Dictionary:
	var idx := night - 1
	if idx < 0 or idx >= nights.size():
		return {}
	return nights[idx]


func rules_active_on(night: int) -> Array[Rule]:
	var out: Array[Rule] = []
	for r in rules:
		if r.unlock_night <= night:
			out.append(r)
	return out


# ── 內部 ──

func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		load_errors.append("找不到 " + path)
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	var json := JSON.new()
	var err := json.parse(f.get_as_text())
	if err != OK:
		load_errors.append("%s 第 %d 行: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


func _load_applicants() -> void:
	var data = _read_json(APPLICANTS_PATH)
	if typeof(data) != TYPE_ARRAY:
		return
	for entry in data:
		var a := Applicant.from_dict(entry)
		if a.id == "":
			load_errors.append("applicants.json 有一筆沒有 id")
			continue
		if applicants.has(a.id):
			load_errors.append("applicants.json 重複 id: " + a.id)
		applicants[a.id] = a


func _load_rules() -> void:
	var data = _read_json(RULES_PATH)
	if typeof(data) != TYPE_ARRAY:
		return
	for entry in data:
		rules.append(Rule.from_dict(entry))


func _load_nights() -> void:
	var data = _read_json(NIGHTS_PATH)
	if typeof(data) != TYPE_ARRAY:
		return
	nights = data


func _load_questions() -> void:
	var data = _read_json(QUESTIONS_PATH)
	if typeof(data) != TYPE_DICTIONARY:
		return
	questions = data
