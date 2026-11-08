extends Node
## 全域事件匯流排。所有玩家行為與系統狀態變化都從這裡發出，
## 系統之間不直接互相引用。

# ── 夜晚流程 ──
signal night_started(night: int)
signal applicant_arrived(applicant: Applicant)
signal applicant_resolved(applicant: Applicant, verdict: Dictionary)
signal queue_empty()
signal settlement_started()
signal settlement_finished(report: Dictionary)
signal night_ended(night: int)
signal game_over(reason: String)

# ── 玩家行為（規則引擎只監聽這些）──
signal stamp_pressed(applicant_id: String, stamp: String)        # approve / deny / report
signal question_asked(applicant_id: String, question_id: String)
signal dialogue_choice(applicant_id: String, node_id: String, option_text: String, tone: String)
signal document_inspected(applicant_id: String, doc_id: String, side: String)
signal applicant_placed(applicant_id: String, floor: int, room: int)
signal applicant_removed(applicant_id: String, floor: int, room: int)
signal jiaobei_thrown(rule_id: String, result: String)           # 聖筊 / 笑筊 / 陰筊

# ── 狀態變化 ──
signal axis_changed(resident_id: String, old_value: int, new_value: int)
signal chaos_changed(old_value: int, new_value: int)
signal strike_added(total: int, reason: String)
signal pay_changed(amount: int)
signal note_updated(key: String, value: Variant)
