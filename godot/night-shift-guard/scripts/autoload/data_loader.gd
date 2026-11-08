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
	_load_questions()
	_load_applicants()
	_load_rules()
	_load_nights()
	for a in applicants.values():
		if not a.has_dialogue():
			a.dialogue = synthesize_dialogue(a)
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


# ── 自動合成對話樹 ─────────────────────────────────────────
## 給沒有手寫 dialogue 的登記者一棵 3–5 回合的基本樹：
##   開場（intro_line）→ 你選一個問題 → 對方回答 → 你選語氣回應 → 對方反應 → 回到剩下的問題 → 結束
## 語氣：kind / neutral / harsh。harsh 對故事鬼會推執念（NightController 結算 temper）。
func synthesize_dialogue(a: Applicant) -> Dictionary:
	var nodes: Dictionary = {}
	var qids: Array = []
	for qid in questions.keys():
		if a.answers.has(qid):
			qids.append(qid)
	var is_ghost := a.is_ghost()
	var is_human := a.kind == Applicant.Kind.HUMAN or a.kind == Applicant.Kind.HUMAN_DISGUISED

	# 開場節點：列出可問的問題 + 直接請他等
	var start_opts: Array = []
	for qid in qids:
		start_opts.append({"text": questions[qid].get("text", qid), "next": "ans_" + qid, "tone": "neutral"})
	start_opts.append({"text": "「好，我看一下文件。」", "next": "", "tone": "neutral"})
	nodes["start"] = {"line": a.intro_line, "options": start_opts}

	for qid in qids:
		var ans: Dictionary = a.answers[qid]
		var contradicts: Array = ans.get("contradicts", [])
		# 回答節點 → 三種語氣回應
		var react_opts: Array = []
		react_opts.append({"text": _kind_reply(is_ghost), "next": "re_k_" + qid, "tone": "kind"})
		react_opts.append({"text": "「好，我知道了。」", "next": "re_n_" + qid, "tone": "neutral"})
		react_opts.append({"text": _harsh_reply(is_ghost), "next": "re_h_" + qid, "tone": "harsh"})
		if not contradicts.is_empty():
			react_opts.insert(0, {"text": "「等等，這跟你文件上寫的不一樣。」", "next": "re_c_" + qid, "tone": "neutral", "contradicts": contradicts, "note": "說的跟文件對不上"})
		nodes["ans_" + qid] = {"line": ans.get("text", "……"), "options": react_opts}
		# 反應節點 → 回到其餘問題
		var rest: Array = []
		for other in qids:
			if other != qid:
				rest.append({"text": questions[other].get("text", other), "next": "ans_" + other, "tone": "neutral"})
		rest.append({"text": "「好，我看一下文件。」", "next": "", "tone": "neutral"})
		nodes["re_k_" + qid] = {"line": _kind_reaction(a, is_ghost, is_human), "options": rest}
		nodes["re_n_" + qid] = {"line": "……", "options": rest}
		nodes["re_h_" + qid] = {"line": _harsh_reaction(a, is_ghost, is_human), "options": rest, "effects": []}
		if not contradicts.is_empty():
			nodes["re_c_" + qid] = {"line": _caught_reaction(a), "options": rest}
	return {"start": "start", "nodes": nodes}


func _kind_reply(is_ghost: bool) -> String:
	return "「辛苦了。您先坐，我馬上幫您處理。」" if is_ghost else "「別急，慢慢說。」"


func _harsh_reply(is_ghost: bool) -> String:
	return "「講重點。後面還有人。」" if is_ghost else "「這裡不是給你住的，走。」"


func _kind_reaction(a: Applicant, is_ghost: bool, is_human: bool) -> String:
	if a.kind == Applicant.Kind.INSPECTOR:
		return "你很客氣。客氣不在評分項目裡。"
	if is_ghost:
		return "……謝謝。很久沒有人這樣跟我說話了。"
	return "謝謝你、謝謝你。我就知道你是好人。那我可以進去了嗎？"


func _harsh_reaction(a: Applicant, is_ghost: bool, is_human: bool) -> String:
	if a.kind == Applicant.Kind.INSPECTOR:
		return "（他在本子上寫了一筆。）"
	if is_ghost:
		return "（他沒有說話。櫃檯的燈閃了一下。）"
	return "你什麼態度！我要投訴你！……你們這裡有管理員嗎？"


func _caught_reaction(a: Applicant) -> String:
	match a.kind:
		Applicant.Kind.HUMAN_DISGUISED:
			return "……你看錯了。那是筆誤。死人填表格也會筆誤。"
		Applicant.Kind.HUMAN:
			return "我……我剛剛講錯了。我太緊張了。"
		_:
			return "是嗎？我不記得了。死了之後很多事都記不清。"
