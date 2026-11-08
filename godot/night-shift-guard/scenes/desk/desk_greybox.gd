extends Control
## 灰盒櫃檯 v2。全部 UI 用程式建，零美術。
## 版面（960×540）：
##   上：狀態列
##   左：登記者（第一句、畫面線索、文件按鈕、問句、擲筊、三個章）
##   中：桌面——兩份文件並排比對
##   右：房間表 3×4
##   下：分頁（事件 log / 筆記本 / 今晚規矩）
## F1：Debug 面板。

var night: NightController
var selected_room: Vector2i = Vector2i(-1, -1)
var held_id: String = ""                 # 拿起來準備搬房的住戶
var jiaobei_left: int = 0
var next_slot: int = 0                   # 下一份文件放哪個桌面格（0/1）
var tonight_mistakes: Array[String] = [] # 白天報紙用
var show_truth: bool = false             # Debug：顯示真相

# ── UI 節點 ──
var top_bar: Label
var left_panel: VBoxContainer
var desk_slots: Array[RichTextLabel] = []
var desk_slot_titles: Array[Label] = []
var right_panel: VBoxContainer
var room_buttons: Array = []
var tabs: TabContainer
var log_box: RichTextLabel
var notebook: RichTextLabel
var rules_box: RichTextLabel
var overlay: PanelContainer
var overlay_label: RichTextLabel
var overlay_button: Button
var debug_panel: PanelContainer


func _ready() -> void:
	night = NightController.new()
	add_child(night)
	_build_ui()
	_connect_bus()
	if GameState.load_save():
		_log("讀到存檔：第 %d 晚，第 %d 任保全" % [GameState.night, GameState.guard_generation])
	_refresh_notebook()
	_show_overlay("[b]夜班保全[/b]\n\n福德宮香客大樓 夜間櫃檯\n\n對人兇，對鬼客氣。\n只有死人才能入住，而且仇家不能同層。\n\n[color=gray]F1 開 Debug 面板　A/D/R 蓋章[/color]", "打卡上班", _on_clock_in)


# ───────────────────────── UI 建構 ─────────────────────────

func _build_ui() -> void:
	top_bar = Label.new()
	top_bar.position = Vector2(12, 6)
	top_bar.size = Vector2(936, 24)
	add_child(top_bar)

	var cols := HBoxContainer.new()
	cols.position = Vector2(12, 34)
	cols.size = Vector2(936, 396)
	cols.add_theme_constant_override("separation", 8)
	add_child(cols)

	left_panel = _panel(cols, 268, 396, "登記者")
	var desk := _panel(cols, 400, 396, "桌面（點文件放上來，兩份並排）")
	right_panel = _panel(cols, 252, 396, "房間表")

	# 桌面：兩格
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 6)
	slots.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desk.add_child(slots)
	for i in 2:
		var pc := PanelContainer.new()
		pc.custom_minimum_size = Vector2(190, 330)
		pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.93, 0.90, 0.80)
		sb.set_content_margin_all(8)
		pc.add_theme_stylebox_override("panel", sb)
		slots.add_child(pc)
		var vb := VBoxContainer.new()
		pc.add_child(vb)
		var t := Label.new()
		t.text = "（空）"
		t.add_theme_color_override("font_color", Color(0.2, 0.15, 0.1))
		vb.add_child(t)
		var rt := RichTextLabel.new()
		rt.bbcode_enabled = true
		rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
		rt.add_theme_color_override("default_color", Color(0.12, 0.1, 0.08))
		vb.add_child(rt)
		desk_slots.append(rt)
		desk_slot_titles.append(t)
	var clear_btn := Button.new()
	clear_btn.text = "清桌"
	clear_btn.pressed.connect(_clear_desk)
	desk.add_child(clear_btn)

	# 房間表
	var grid := GridContainer.new()
	grid.columns = GameState.ROOMS_PER_FLOOR
	right_panel.add_child(grid)
	room_buttons.clear()
	for f in range(GameState.FLOORS - 1, -1, -1):
		var row: Array = []
		for r in GameState.ROOMS_PER_FLOOR:
			var b := Button.new()
			b.custom_minimum_size = Vector2(56, 44)
			b.text = "%dF-%d" % [f + 1, r + 1]
			b.pressed.connect(_on_room_pressed.bind(f, r))
			grid.add_child(b)
			row.append(b)
		room_buttons.insert(0, row)
	var hint := Label.new()
	hint.text = "空房：點選 → 蓋「准予入住」\n已入住：點一下拿起，再點空房搬過去\n故事鬼會留宿；通用鬼天亮就走"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	right_panel.add_child(hint)

	# 下方分頁
	tabs = TabContainer.new()
	tabs.position = Vector2(12, 436)
	tabs.size = Vector2(936, 98)
	add_child(tabs)
	log_box = RichTextLabel.new()
	log_box.name = "事件"
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	tabs.add_child(log_box)
	notebook = RichTextLabel.new()
	notebook.name = "筆記本"
	notebook.bbcode_enabled = true
	tabs.add_child(notebook)
	rules_box = RichTextLabel.new()
	rules_box.name = "今晚規矩"
	rules_box.bbcode_enabled = true
	tabs.add_child(rules_box)

	# 遮罩
	overlay = PanelContainer.new()
	overlay.position = Vector2(140, 40)
	overlay.size = Vector2(680, 460)
	var osb := StyleBoxFlat.new()
	osb.bg_color = Color(0.09, 0.09, 0.13, 1.0)
	osb.border_color = Color(0.78, 0.64, 0.29, 1.0)
	osb.set_border_width_all(2)
	osb.set_content_margin_all(16)
	overlay.add_theme_stylebox_override("panel", osb)
	add_child(overlay)
	var ovb := VBoxContainer.new()
	overlay.add_child(ovb)
	overlay_label = RichTextLabel.new()
	overlay_label.bbcode_enabled = true
	overlay_label.custom_minimum_size = Vector2(640, 380)
	ovb.add_child(overlay_label)
	overlay_button = Button.new()
	ovb.add_child(overlay_button)
	overlay.visible = false

	_build_debug_panel()


func _panel(parent: Control, width: int, height: int, title: String) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(width, height)
	parent.add_child(pc)
	var vb := VBoxContainer.new()
	pc.add_child(vb)
	var t := Label.new()
	t.text = "── " + title + " ──"
	t.add_theme_font_size_override("font_size", 13)
	vb.add_child(t)
	return vb


func _build_debug_panel() -> void:
	debug_panel = PanelContainer.new()
	debug_panel.position = Vector2(700, 34)
	debug_panel.size = Vector2(248, 200)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.05, 0.05, 0.95)
	sb.set_content_margin_all(8)
	debug_panel.add_theme_stylebox_override("panel", sb)
	add_child(debug_panel)
	var vb := VBoxContainer.new()
	debug_panel.add_child(vb)
	var t := Label.new()
	t.text = "DEBUG（F1 關閉）"
	vb.add_child(t)
	_dbg_button(vb, "顯示真相（人/鬼）", func(): show_truth = not show_truth; if night.current: _on_applicant_arrived(night.current))
	_dbg_button(vb, "跳過本晚剩餘登記者", func():
		if night.state == NightController.State.QUEUE:
			night.queue.clear()
			night.current = null
			night.settle()
	)
	_dbg_button(vb, "混亂 +1", func(): GameState.add_chaos(1))
	_dbg_button(vb, "記點 +1", func(): GameState.add_strike("debug"))
	_dbg_button(vb, "重置存檔並重開", func(): GameState.reset_all(); get_tree().reload_current_scene())
	debug_panel.visible = false


func _dbg_button(parent: Control, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)


func _connect_bus() -> void:
	EventBus.night_started.connect(_on_night_started)
	EventBus.applicant_arrived.connect(_on_applicant_arrived)
	EventBus.applicant_resolved.connect(_on_applicant_resolved)
	EventBus.settlement_finished.connect(_on_settlement)
	EventBus.strike_added.connect(func(total, reason): _log("[color=red]記點 %d/%d：%s[/color]" % [total, GameState.MAX_STRIKES, reason]); _refresh_top())
	EventBus.chaos_changed.connect(func(_o, n): _log("混亂 → %d" % n); _refresh_top())
	EventBus.axis_changed.connect(func(id, o, n): _log("%s 執念 %d → %d" % [_name_of(id), o, n]))
	EventBus.pay_changed.connect(func(_a): _refresh_top())
	EventBus.note_updated.connect(func(_k, _v): _refresh_notebook())
	EventBus.game_over.connect(_on_game_over)


# ───────────────────────── 流程 ─────────────────────────

func _on_clock_in() -> void:
	_hide_overlay()
	night.start_night()
	var cfg := DataLoader.night_config(GameState.night)
	_show_overlay("[b]%s[/b]\n\n[color=gold]公告欄[/color]\n%s\n\n[color=gold]今晚生效的規矩[/color]\n%s\n\n擲筊額度：%d 次" % [
		cfg.get("title", ""), cfg.get("notice", ""), _rules_text(), jiaobei_left
	], "開始接待", func(): _hide_overlay(); night.open_desk())


func _on_night_started(n: int) -> void:
	var cfg := DataLoader.night_config(n)
	jiaobei_left = int(cfg.get("jiaobei_uses", 3))
	tonight_mistakes.clear()
	_refresh_top()
	_refresh_rules()
	_log("[color=yellow]第 %d 晚開始[/color]" % n)


func _rules_text() -> String:
	var lines: PackedStringArray = []
	for r in night.active_rules:
		lines.append("• " + r.text_shown)
	return "\n".join(lines)


func _on_applicant_arrived(a: Applicant) -> void:
	selected_room = Vector2i(-1, -1)
	_clear_desk()
	_refresh_rooms()
	_clear(left_panel, 1)

	var name_l := Label.new()
	name_l.text = "【%s】" % a.display_name
	if show_truth:
		name_l.text += "  [%s]" % Applicant.Kind.keys()[a.kind]
	left_panel.add_child(name_l)
	var intro := Label.new()
	intro.text = "「%s」" % a.intro_line
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override("font_size", 13)
	left_panel.add_child(intro)

	var tells: PackedStringArray = []
	if _rule_active("shadow"):
		tells.append("影子：%s" % ("[color=orange]有[/color]" if a.has_shadow else "無"))
	if _rule_active("feet"):
		tells.append("腳：%s" % ("[color=orange]著地[/color]" if a.feet_on_ground else "懸空"))
	var visual := RichTextLabel.new()
	visual.bbcode_enabled = true
	visual.fit_content = true
	visual.text = "　".join(tells) if not tells.is_empty() else "[color=gray]（畫面線索尚未解鎖）[/color]"
	left_panel.add_child(visual)

	# 文件
	var docs_row := HFlowContainer.new()
	left_panel.add_child(docs_row)
	if a.documents.is_empty():
		var none := Label.new()
		none.text = "（沒有任何文件）"
		none.add_theme_color_override("font_color", Color(1, 0.6, 0.3))
		docs_row.add_child(none)
	for d in a.documents:
		var btn := Button.new()
		btn.text = "◆ " + d.title
		btn.pressed.connect(_show_document.bind(a, d))
		docs_row.add_child(btn)

	# 問句
	for qid in DataLoader.questions.keys():
		if not a.answers.has(qid):
			continue
		var qb := Button.new()
		qb.text = DataLoader.questions[qid].get("text", qid)
		qb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		qb.add_theme_font_size_override("font_size", 13)
		qb.pressed.connect(func():
			EventBus.question_asked.emit(a.id, qid)
			_log("你：%s　%s：「%s」" % [qb.text, a.display_name, a.answers[qid].get("text", "")])
			qb.text = "✓ " + qb.text
			qb.disabled = true
		)
		left_panel.add_child(qb)

	# 擲筊
	var jb := Button.new()
	jb.text = "擲筊問土地公（剩 %d）" % jiaobei_left
	jb.disabled = jiaobei_left <= 0
	jb.pressed.connect(func(): _throw_jiaobei(a); jb.text = "擲筊問土地公（剩 %d）" % jiaobei_left; jb.disabled = jiaobei_left <= 0)
	left_panel.add_child(jb)

	left_panel.add_child(HSeparator.new())
	var stamps := HBoxContainer.new()
	left_panel.add_child(stamps)
	for pair in [["✓ 准予入住", Judge.STAMP_APPROVE], ["× 拒絕", Judge.STAMP_DENY], ["☎ 通報", Judge.STAMP_REPORT]]:
		var sbtn := Button.new()
		sbtn.text = pair[0]
		sbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sbtn.pressed.connect(_on_stamp.bind(pair[1]))
		stamps.add_child(sbtn)

	_log("[color=aqua]→ %s 走到櫃檯[/color]" % a.display_name)


func _show_document(a: Applicant, d: Document) -> void:
	EventBus.document_inspected.emit(a.id, d.id, "front")
	var lines: PackedStringArray = []
	for k in d.fields.keys():
		lines.append("[b]%s[/b]　%s" % [k, d.fields[k]])
	if not d.back_fields.is_empty():
		lines.append("[color=#665]── 背面 ──[/color]")
		for k in d.back_fields.keys():
			lines.append("[b]%s[/b]　%s" % [k, d.back_fields[k]])
	lines.append("[color=#665]章：%s[/color]" % (_stamps_text(d.stamps) if not d.stamps.is_empty() else "（無）"))
	desk_slot_titles[next_slot].text = "%s · %s" % [a.display_name, d.title]
	desk_slots[next_slot].text = "\n".join(lines)
	next_slot = 1 - next_slot


func _stamps_text(stamps: Array[String]) -> String:
	var names := {
		"cancelled": "【註銷】", "hospital": "醫院章", "household_office": "戶政章",
		"prosecutor": "地檢署相驗章", "funeral_home": "殯葬業章", "committee": "管委會章",
	}
	var out: PackedStringArray = []
	for s in stamps:
		out.append(names.get(s, s))
	return "、".join(out)


func _clear_desk() -> void:
	for i in 2:
		desk_slot_titles[i].text = "（空）"
		desk_slots[i].text = ""
	next_slot = 0


func _throw_jiaobei(a: Applicant) -> void:
	if jiaobei_left <= 0:
		return
	jiaobei_left -= 1
	var clash := Judge.available_tells(a, night.active_rules).has("almanac_clash")
	var result: String
	var text: String
	match a.kind:
		Applicant.Kind.GHOST:
			if clash:
				result = "笑筊"
				text = "土地公笑了一下，沒回答。"
			else:
				result = "聖筊"
				text = "聖筊。土地公說：這位可以。"
		Applicant.Kind.HUMAN:
			result = "陰筊"
			text = "陰筊。土地公說：不行。"
		_:
			result = "笑筊"
			text = "笑筊。土地公沒有回答——祂不想替你決定這個。"
	EventBus.jiaobei_thrown.emit(a.id, result)
	_log("[color=gold]擲筊：%s[/color]　%s" % [result, text])


func _on_stamp(stamp_id: String) -> void:
	var a := night.current
	if a == null:
		return
	if held_id != "":
		_log("[color=orange]手上還拿著住戶，先放下[/color]")
		return
	if stamp_id == Judge.STAMP_APPROVE:
		if selected_room == Vector2i(-1, -1):
			_log("[color=orange]先在房間表選一格[/color]")
			return
		if not GameState.place(a, selected_room.x, selected_room.y):
			_log("[color=orange]那間已經有人[/color]")
			return
	night.stamp(stamp_id)


func _on_applicant_resolved(a: Applicant, verdict: Dictionary) -> void:
	if verdict["correct"]:
		_log("[color=lime]✓ 正確[/color]（+%d）" % GameState.pay_per_correct)
	else:
		var missed: Array = verdict["missed_checks"]
		_log("[color=red]× %s[/color]%s" % [verdict["reason"], ("　可用線索：" + ", ".join(missed)) if not missed.is_empty() else ""])
		tonight_mistakes.append("%s：%s" % [a.display_name, verdict["reason"]])
		if verdict["stamp"] == Judge.STAMP_DENY and a.plea_line != "":
			_log("%s：「%s」" % [a.display_name, a.plea_line])
	_refresh_rooms()
	_refresh_top()
	_refresh_notebook()


func _on_settlement(report: Dictionary) -> void:
	var lines: PackedStringArray = ["[b]天亮了 — 第 %d 晚[/b]" % report["night"]]
	lines.append("正確 %d　錯誤 %d　薪水 %d　混亂 %d　記點 %d" % [report["correct"], report["wrong"], report["pay"], report["chaos"], report["strikes"]])
	if (report["events"] as Array).is_empty():
		lines.append("\n夜裡很安靜。")
	else:
		lines.append("\n[color=orange]夜裡發生的事[/color]")
		for ev in report["events"]:
			lines.append("　%dF：%s" % [ev["floor"] + 1, ev["text"]])
	if not (report.get("departed", []) as Array).is_empty():
		lines.append("\n天亮前被引路走的：%s" % "、".join(report["departed"]))
	# 報紙
	lines.append("\n[color=gold]今日報紙[/color]")
	if tonight_mistakes.is_empty():
		lines.append("　八里山區一夜平安。")
	else:
		for m in tonight_mistakes:
			lines.append("　" + _headline_for(m))
	# 投訴信
	var complaints: PackedStringArray = []
	for id in report["axis"].keys():
		var v: int = report["axis"][id]
		if v >= 40:
			complaints.append("　%s 的投訴信：「你把我排在誰旁邊，你知道嗎。」（執念 %d）" % [_name_of(id), v])
		elif v <= -60:
			complaints.append("　%s 留了一張紙條：「謝謝。」（執念 %d）" % [_name_of(id), v])
	if not complaints.is_empty():
		lines.append("\n[color=gold]信箱[/color]")
		lines.append_array(complaints)
	lines.append("\n債務剩餘：%d" % maxi(GameState.debt - report["pay"], 0))
	_show_overlay("\n".join(lines), "回家睡覺", func():
		_hide_overlay()
		night.end_day()
		if night.state != NightController.State.ENDED:
			_on_clock_in()
	)


func _headline_for(m: String) -> String:
	if m.contains("活人"):
		return "山區民宿傳失蹤　家屬：他說要去借廁所"
	if m.contains("拒絕了真正的鬼"):
		return "龍米路深夜有人徘徊　居民稱「看起來像在找地方住」"
	if m.contains("沖煞"):
		return "廟方：昨夜有客人不該進門"
	if m.contains("抽查員"):
		return "福德宮管委會發函：夜班人員態度待改善"
	return "八里山區昨夜不平靜"


func _on_game_over(reason: String) -> void:
	var text := ""
	var btn := ""
	var cb: Callable
	match reason:
		"strikes":
			text = "[b]你被換掉了。[/b]\n\n管委會的公文今天早上到。\n下一任保全會拿到你的筆記本。\n\n（天數不重置：第 %d 晚重來）" % GameState.night
			btn = "交接給下一任"
			cb = func(): _hide_overlay(); night.replace_guard_and_restart(); _on_clock_in_after_replace()
		"ending_cleared":
			text = "[b]結局：清空[/b]\n\n鬼門關上了。大樓空了。\n土地公第一次走出來，請你喝茶。"
			btn = "重新開始"
			cb = func(): GameState.reset_all(); _hide_overlay(); _on_clock_in()
		"ending_fallen":
			text = "[b]結局：淪陷[/b]\n\n牠們沒走。你也走不了。\n明天還是會有人來登記。"
			btn = "重新開始"
			cb = func(): GameState.reset_all(); _hide_overlay(); _on_clock_in()
		_:
			text = "[b]結局：平衡[/b]\n\n債還清了。你走下山。\n後面有腳步聲，你沒有回頭。"
			btn = "重新開始"
			cb = func(): GameState.reset_all(); _hide_overlay(); _on_clock_in()
	_show_overlay(text, btn, cb)


func _on_clock_in_after_replace() -> void:
	var cfg := DataLoader.night_config(GameState.night)
	_show_overlay("[b]第 %d 任保全[/b]\n\n前任留下的筆記本：\n%s\n\n%s" % [
		GameState.guard_generation, _notes_text(), cfg.get("notice", "")
	], "開始接待", func(): _hide_overlay(); night.open_desk())


# ───────────────────────── 房間 ─────────────────────────

func _on_room_pressed(f: int, r: int) -> void:
	var occupant: String = GameState.rooms[f][r]
	if held_id != "":
		if occupant == "":
			var a: Applicant = GameState.residents.get(held_id)
			GameState.place(a, f, r)
			_log("%s 搬到 %dF-%d" % [a.display_name, f + 1, r + 1])
			held_id = ""
		elif occupant == held_id:
			held_id = ""
		else:
			_log("[color=orange]那間有人，先選空房[/color]")
	elif occupant != "":
		held_id = occupant
		GameState.remove_from_room(f, r)
		_log("拿起 %s，點一間空房放下" % _name_of(occupant))
	else:
		selected_room = Vector2i(f, r)
	_refresh_rooms()


func _refresh_rooms() -> void:
	for f in GameState.FLOORS:
		for r in GameState.ROOMS_PER_FLOOR:
			var b: Button = room_buttons[f][r]
			var id: String = GameState.rooms[f][r]
			b.text = _name_of(id) if id != "" else "%dF-%d" % [f + 1, r + 1]
			b.modulate = Color(1, 0.9, 0.4) if selected_room == Vector2i(f, r) else Color.WHITE
			if held_id != "" and id == "":
				b.modulate = Color(0.6, 1, 0.7)
			if GameState.damaged_floors.has(f):
				b.modulate = Color(0.6, 0.3, 0.3)


# ───────────────────────── 分頁 ─────────────────────────

func _refresh_top() -> void:
	top_bar.text = "第 %d 晚 ｜ 第 %d 任 ｜ 薪水 %d ｜ 債務 %d ｜ 混亂 %d/10 ｜ 記點 %d/%d ｜ 擲筊 %d" % [
		GameState.night, GameState.guard_generation, GameState.tonight_pay, GameState.debt,
		GameState.chaos, GameState.strikes, GameState.MAX_STRIKES, jiaobei_left
	]


func _refresh_rules() -> void:
	rules_box.text = _rules_text()


func _refresh_notebook() -> void:
	var lines: PackedStringArray = []
	var rel: Dictionary = GameState.notes.get("relations", {})
	lines.append("[b]已知關係[/b]　" + ("（還沒發現任何關係——仇家同層出事後會自動記下）" if rel.is_empty() else ""))
	for k in rel.keys():
		var parts: PackedStringArray = k.split("|")
		lines.append("　%s ↔ %s：%s" % [_name_of(parts[0]), _name_of(parts[1]), _relation_label(rel[k])])
	var seen: Dictionary = GameState.notes.get("applicants_seen", {})
	var ghosts: PackedStringArray = []
	var humans: PackedStringArray = []
	for id in seen.keys():
		if seen[id] == "ghost":
			ghosts.append(_name_of(id))
		else:
			humans.append(_name_of(id))
	lines.append("[b]見過的鬼[/b]　" + "、".join(ghosts))
	lines.append("[b]見過的活人[/b]　" + "、".join(humans))
	notebook.text = "\n".join(lines)


func _relation_label(kind: String) -> String:
	match kind:
		"hostile": return "仇家"
		"family": return "家人"
		"debt": return "債務"
		"property": return "產權糾紛"
		"zodiac": return "生肖相沖"
		_: return kind


func _notes_text() -> String:
	var rel: Dictionary = GameState.notes.get("relations", {})
	if rel.is_empty():
		return "（空白）"
	var lines: PackedStringArray = []
	for k in rel.keys():
		var parts: PackedStringArray = k.split("|")
		lines.append("　%s ↔ %s：%s" % [_name_of(parts[0]), _name_of(parts[1]), _relation_label(rel[k])])
	return "\n".join(lines)


# ───────────────────────── 小工具 ─────────────────────────

func _name_of(id: String) -> String:
	var a := DataLoader.get_applicant(id)
	return a.display_name if a else id


func _rule_active(check_id: String) -> bool:
	for r in night.active_rules:
		if r.check_id == check_id:
			return true
	return false


func _show_overlay(text: String, button_text: String, on_press: Callable) -> void:
	overlay_label.text = text
	overlay_button.text = button_text
	for c in overlay_button.pressed.get_connections():
		overlay_button.pressed.disconnect(c["callable"])
	overlay_button.pressed.connect(on_press)
	overlay.visible = true


func _hide_overlay() -> void:
	overlay.visible = false


func _clear(container: Control, keep_first: int) -> void:
	var children := container.get_children()
	for i in range(keep_first, children.size()):
		children[i].queue_free()


func _log(text: String) -> void:
	log_box.append_text(text + "\n")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F1:
		debug_panel.visible = not debug_panel.visible
		return
	if overlay.visible or night.current == null:
		return
	if event.is_action_pressed("ui_stamp_approve"):
		_on_stamp(Judge.STAMP_APPROVE)
	elif event.is_action_pressed("ui_stamp_deny"):
		_on_stamp(Judge.STAMP_DENY)
	elif event.is_action_pressed("ui_stamp_report"):
		_on_stamp(Judge.STAMP_REPORT)
