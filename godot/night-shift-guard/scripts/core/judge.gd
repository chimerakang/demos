class_name Judge
extends RefCounted
## 審核判定引擎。
## 輸入：登記者 + 玩家蓋的章 + 本晚啟用的 CHECK 規則
## 輸出：{correct, reason, missed_checks[], consequences[]}
##
## 「正確」的定義：
##   鬼           → approve
##   活人 / 假冒  → deny（report 也算對，但薪水較低）
##   抽查員       → approve（牠文件完美，拒絕會被記點）
##
## missed_checks 是玩家本來可以用來抓到破綻的檢查點，給結算畫面與遙測用。

const STAMP_APPROVE := "approve"
const STAMP_DENY := "deny"
const STAMP_REPORT := "report"


static func evaluate(a: Applicant, stamp: String, active_rules: Array[Rule]) -> Dictionary:
	var should_admit := a.should_be_admitted() or a.kind == Applicant.Kind.INSPECTOR
	# 農民曆沖煞：真鬼但今晚不能收（規則解鎖後才算）
	var clash_tonight := false
	for r in active_rules:
		if r.kind == Rule.Kind.CHECK and r.check_id == "almanac_clash" and check_fires(r, a):
			clash_tonight = true
	if clash_tonight:
		should_admit = false
	var correct: bool
	var reason := ""

	match stamp:
		STAMP_APPROVE:
			correct = should_admit
			if not correct:
				reason = "沖煞日收了不該收的客人" if clash_tonight else "放了活人進來"
		STAMP_DENY:
			correct = not should_admit
			if not correct:
				reason = "拒絕了真正的鬼" if a.is_ghost() else "拒絕了管委會抽查員"
		STAMP_REPORT:
			correct = (a.kind == Applicant.Kind.HUMAN_DISGUISED)
			if not correct:
				reason = "誤報" if a.is_ghost() else "通報了不需要通報的對象"
		_:
			correct = false
			reason = "未知的章"

	var result := {
		"correct": correct,
		"reason": reason,
		"stamp": stamp,
		"missed_checks": [] as Array[String],
		"consequences": [] as Array[Dictionary],
	}

	if not correct:
		result["missed_checks"] = available_tells(a, active_rules)
		result["consequences"] = [{"kind": "strike", "reason": reason}, {"kind": "chaos", "value": 1}]
		if stamp == STAMP_APPROVE and not should_admit and not clash_tonight:
			# 活人進來 → 當晚死亡，隔晚變鬼回來
			result["consequences"].append({"kind": "human_admitted", "applicant": a.id, "return_as": a.return_as})
	else:
		var pay := GameState.pay_per_correct
		if stamp == STAMP_REPORT:
			pay = int(pay * 0.6)
		result["consequences"] = [{"kind": "pay", "value": pay}]

	return result


## 列出這位登記者身上「本晚已解鎖的檢查點能抓到」的破綻。
static func available_tells(a: Applicant, active_rules: Array[Rule]) -> Array[String]:
	var tells: Array[String] = []
	for r in active_rules:
		if r.kind != Rule.Kind.CHECK:
			continue
		if check_fires(r, a):
			tells.append(r.check_id)
	return tells


## 單一檢查點對單一登記者是否「亮起」（= 這個人有這個破綻）。
## 新增檢查點時只需要在這裡加一個 match 分支 + rules.json 一筆。
static func check_fires(r: Rule, a: Applicant) -> bool:
	match r.check_id:
		"has_death_cert":
			return _doc_of_type(a, Document.Type.DEATH_CERT) == null
		"id_cancelled":
			var idc := _doc_of_type(a, Document.Type.ID_CARD)
			return idc != null and not idc.stamps.has("cancelled")
		"shadow":
			return a.has_shadow
		"feet":
			return a.feet_on_ground
		"answer_contradiction":
			for q in a.answers.keys():
				if not (a.answers[q].get("contradicts", []) as Array).is_empty():
					return true
			return false
		"almanac_clash":
			return a.visual_tells.has("almanac_clash")
		"forged_document":
			for d in a.documents:
				if d.is_forged:
					return true
			return false
		"removal_date_future":
			var hr := _doc_of_type(a, Document.Type.HOUSEHOLD_REMOVAL)
			return hr != null and hr.has_flaw("date_future")
		_:
			# 未知 check_id：看 visual_tells 有沒有同名 tag，方便資料端先實驗
			return a.visual_tells.has(r.check_id)


static func _doc_of_type(a: Applicant, t: Document.Type) -> Document:
	for d in a.documents:
		if d.type == t:
			return d
	return null
