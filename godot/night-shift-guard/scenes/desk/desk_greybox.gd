extends Control
## 灰盒櫃檯。全部 UI 用程式建，零美術，目標是把一晚的循環跑通：
## 開班公告 → 登記者（文件 / 問答 / 排房 / 蓋章）→ 結算 → 白天 → 下一晚。
## 之後正式 desk 場景會取代這支，但 NightController 與資料層不變。

var night: NightController
var selected_room: Vector2i = Vector2i(-1, -1)

# ── UI 節點 ──
var top_bar: Label
var left_panel: VBoxContainer       # 登記者 + 文件
var mid_panel: VBoxContainer        # 問答 + 章
var right_panel: VBoxContainer      # 房間表 + 筆記
var overlay: PanelContainer         # 公告 / 結算 / 白天 / 結局
var overlay_label: RichTextLabel
var overlay_button: Button
var room_buttons: Array = []        # [floor][room] -> Button
var log_box: RichTextLabel


func _ready() -> void:
	night = NightController.new()
	add_child(night)
	_build_ui()
	_connect_bus()
	if GameState.load_save():
		_log("讀到存檔：第 %d 晚，第 %d 任保全" % [GameState.night, GameState.guard_generation])
	_show_overlay("[b]夜班保全[/b]\n\n福德宮香客大樓 夜間櫃檯\n\n對人兇，對鬼客氣。\n只有死人才能入住，而且仇家不能同層。\n\n（瀏覽器需要先點一下才會有聲音）", "打卡上班", _on_clock_in)


# ───────────────────────── UI 建構 ─────────────────────────

func _build_ui() -> void:
	top_bar = Label.new()
	top_bar.position = Vector2(12, 8)
	top_bar.size = Vector2(936, 24)
	add_child(top_bar)

	var cols := HBoxContainer.new()
	cols.position = Vector2(12, 40)
	cols.size = Vector2(936, 400)
	cols.add_theme_constant_override("separation", 12)
	add_child(cols)

	left_panel = _panel(cols, 340, "登記者")
	mid_panel = _panel(cols, 260, "對講機 / 印章")
	right_panel = _panel(cols, 300, "房間表")

	log_box = RichTextLabel.new()
	log_box.position = Vector2(12, 448)
	log_box.size = Vector2(936, 84)
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	add_child(log_box)

	# 房間表 3×3
	var grid := GridContainer.new()
	grid.columns = GameState.ROOMS_PER_FLOOR
	right_panel.add_child(grid)
	room_buttons.clear()
	for f in range(GameState.FLOORS - 1, -1, -1):   # 高樓層在上
		var row: Array = []
		for r in GameState.ROOMS_PER_FLOOR:
			var b := Button.new()
			b.custom_minimum_size = Vector2(90, 48)
			b.text = "%dF-%d" % [f + 1, r + 1]
			b.pressed.connect(_on_room_pressed.bind(f, r))
			grid.add_child(b)
			row.append(b)
		room_buttons.insert(0, row)
	var hint := Label.new()
	hint.text = "點一格 → 再蓋「准予入住」。再點同格可清空。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_panel.add_child(hint)

	# 遮罩
	overlay = PanelContainer.new()
	overlay.position = Vector2(160, 60)
	overlay.size = Vector2(640, 420)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.09, 0.13, 1.0)
	sb.border_color = Color(0.78, 0.64, 0.29, 1.0)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(16)
	overlay.add_theme_stylebox_override("panel", sb)
	add_child(overlay)
	var vb := VBoxContainer.new()
	overlay.add_child(vb)
	overlay_label = RichTextLabel.new()
	overlay_label.bbcode_enabled = true
	overlay_label.custom_minimum_size = Vector2(600, 340)
	overlay_label.fit_content = false
	vb.add_child(overlay_label)
	overlay_button = Button.new()
	vb.add_child(overlay_button)
	overlay.visible = false


func _panel(parent: Control, width: int, title: String) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(width, 400)
	parent.add_child(pc)
	var vb := VBoxContainer.new()
	pc.add_child(vb)
	var t := Label.new()
	t.text = "── " + title + " ──"
	vb.add_child(t)
	return vb


func _connect_bus() -> void:
	EventBus.night_started.connect(func(n): _refresh_top(); _log("[color=yellow]第 %d 晚開始[/color]" % n))
	EventBus.applicant_arrived.connect(_on_applicant_arrived)
	EventBus.applicant_resolved.connect(_on_applicant_resolved)
	EventBus.settlement_finished.connect(_on_settlement)
	EventBus.strike_added.connect(func(total, reason): _log("[color=red]記點 %d/%d：%s[/color]" % [total, GameState.MAX_STRIKES, reason]); _refresh_top())
	EventBus.chaos_changed.connect(func(_o, n): _log("混亂 → %d" % n); _refresh_top())
	EventBus.axis_changed.connect(func(id, o, n): _log("%s 執念 %d → %d" % [id, o, n]))
	EventBus.pay_changed.connect(func(_a): _refresh_top())
	EventBus.game_over.connect(_on_game_over)


# ───────────────────────── 流程 ─────────────────────────

func _on_clock_in() -> void:
	_hide_overlay()
	night.start_night()
	var cfg := DataLoader.night_config(GameState.night)
	_show_overlay("[b]%s[/b]\n\n公告欄：\n%s\n\n今晚生效的規矩：\n%s" % [
		cfg.get("title", ""), cfg.get("notice", ""), _rules_text()
	], "開始接待", func(): _hide_overlay(); night.open_desk())


func _rules_text() -> String:
	var lines: PackedStringArray = []
	for r in night.active_rules:
		lines.append("• " + r.text_shown)
	return "\n".join(lines)


func _on_applicant_arrived(a: Applicant) -> void:
	selected_room = Vector2i(-1, -1)
	_refresh_rooms()
	_clear(left_panel, 1)
	_clear(mid_panel, 1)

	var name_l := Label.new()
	name_l.text = "【%s】" % a.display_name
	left_panel.add_child(name_l)
	var intro := Label.new()
	intro.text = "「%s」" % a.intro_line
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_panel.add_child(intro)

	var visual := Label.new()
	var tells: PackedStringArray = []
	if night.active_rules.any(func(r): return r.check_id == "shadow"):
		tells.append("影子：%s" % ("有" if a.has_shadow else "無"))
	if night.active_rules.any(func(r): return r.check_id == "feet"):
		tells.append("腳：%s" % ("著地" if a.feet_on_ground else "懸空"))
	visual.text = "  ".join(tells) if not tells.is_empty() else "（畫面線索尚未解鎖）"
	left_panel.add_child(visual)

	var docs_title := Label.new()
	docs_title.text = "文件："
	left_panel.add_child(docs_title)
	if a.documents.is_empty():
		var none := Label.new()
		none.text = "  （沒有任何文件）"
		left_panel.add_child(none)
	for d in a.documents:
		var btn := Button.new()
		btn.text = "◆ " + d.title
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_show_document.bind(a, d))
		left_panel.add_child(btn)

	# 問答
	for qid in DataLoader.questions.keys():
		if not a.answers.has(qid):
			continue
		var qb := Button.new()
		qb.text = DataLoader.questions[qid].get("text", qid)
		qb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		qb.pressed.connect(func():
			EventBus.question_asked.emit(a.id, qid)
			_log("你：%s\n%s：「%s」" % [qb.text, a.display_name, a.answers[qid].get("text", "")])
			qb.disabled = true
		)
		mid_panel.add_child(qb)

	mid_panel.add_child(HSeparator.new())
	var approve := Button.new()
	approve.text = "✓ 准予入住（A）"
	approve.pressed.connect(_on_stamp.bind(Judge.STAMP_APPROVE))
	mid_panel.add_child(approve)
	var deny := Button.new()
	deny.text = "× 拒絕（D）"
	deny.pressed.connect(_on_stamp.bind(Judge.STAMP_DENY))
	mid_panel.add_child(deny)
	var report := Button.new()
	report.text = "☎ 通報管委會（R）"
	report.pressed.connect(_on_stamp.bind(Judge.STAMP_REPORT))
	mid_panel.add_child(report)

	_log("[color=aqua]→ %s 走到櫃檯[/color]" % a.display_name)


func _show_document(a: Applicant, d: Document) -> void:
	EventBus.document_inspected.emit(a.id, d.id, "front")
	var lines: PackedStringArray = ["[b]%s[/b]" % d.title]
	for k in d.fields.keys():
		lines.append("%s：%s" % [k, d.fields[k]])
	if not d.back_fields.is_empty():
		lines.append("\n[i]背面[/i]")
		for k in d.back_fields.keys():
			lines.append("%s：%s" % [k, d.back_fields[k]])
	lines.append("\n章：%s" % (", ".join(d.stamps) if not d.stamps.is_empty() else "（無）"))
	_show_overlay("\n".join(lines), "放回去", _hide_overlay)


func _on_stamp(stamp_id: String) -> void:
	var a := night.current
	if a == null:
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
		_log("[color=red]✗ %s[/color]%s" % [verdict["reason"], ("　可用線索：" + ", ".join(missed)) if not missed.is_empty() else ""])
		if verdict["stamp"] == Judge.STAMP_DENY and a.plea_line != "":
			_log("%s：「%s」" % [a.display_name, a.plea_line])
	_refresh_rooms()
	_refresh_top()


func _on_settlement(report: Dictionary) -> void:
	var lines: PackedStringArray = ["[b]天亮了 — 第 %d 晚結算[/b]\n" % report["night"]]
	lines.append("正確 %d　錯誤 %d　薪水 %d" % [report["correct"], report["wrong"], report["pay"]])
	lines.append("混亂 %d　記點 %d" % [report["chaos"], report["strikes"]])
	if (report["events"] as Array).is_empty():
		lines.append("\n夜裡很安靜。")
	else:
		lines.append("\n[color=orange]夜裡發生的事：[/color]")
		for ev in report["events"]:
			lines.append("  %dF：%s" % [ev["floor"] + 1, ev["text"]])
	if not (report["axis"] as Dictionary).is_empty():
		lines.append("\n執念：")
		for id in report["axis"].keys():
			lines.append("  %s：%d" % [id, report["axis"][id]])
	lines.append("\n債務剩餘：%d" % maxi(GameState.debt - report["pay"], 0))
	_show_overlay("\n".join(lines), "回家睡覺", func():
		_hide_overlay()
		night.end_day()
		if night.state != NightController.State.ENDED:
			_on_clock_in()
	)


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


# ───────────────────────── 小工具 ─────────────────────────

func _on_room_pressed(f: int, r: int) -> void:
	if GameState.rooms[f][r] != "":
		GameState.remove_from_room(f, r)
		_log("清空 %dF-%d" % [f + 1, r + 1])
	else:
		selected_room = Vector2i(f, r)
	_refresh_rooms()


func _refresh_rooms() -> void:
	for f in GameState.FLOORS:
		for r in GameState.ROOMS_PER_FLOOR:
			var b: Button = room_buttons[f][r]
			var id: String = GameState.rooms[f][r]
			if id != "":
				var a := GameState.residents.get(id) as Applicant
				b.text = a.display_name if a else id
			else:
				b.text = "%dF-%d" % [f + 1, r + 1]
			b.modulate = Color(1, 0.9, 0.4) if selected_room == Vector2i(f, r) else Color.WHITE
			if GameState.damaged_floors.has(f):
				b.modulate = Color(0.6, 0.3, 0.3)


func _refresh_top() -> void:
	top_bar.text = "第 %d 晚 ｜ 第 %d 任 ｜ 薪水 %d ｜ 債務 %d ｜ 混亂 %d/10 ｜ 記點 %d/%d" % [
		GameState.night, GameState.guard_generation, GameState.tonight_pay, GameState.debt,
		GameState.chaos, GameState.strikes, GameState.MAX_STRIKES
	]


func _notes_text() -> String:
	var rel: Dictionary = GameState.notes.get("relations", {})
	if rel.is_empty():
		return "（空白）"
	var lines: PackedStringArray = []
	for k in rel.keys():
		lines.append("  %s → %s" % [k.replace("|", " ↔ "), rel[k]])
	return "\n".join(lines)


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
	if overlay.visible or night.current == null:
		return
	if event.is_action_pressed("ui_stamp_approve"):
		_on_stamp(Judge.STAMP_APPROVE)
	elif event.is_action_pressed("ui_stamp_deny"):
		_on_stamp(Judge.STAMP_DENY)
	elif event.is_action_pressed("ui_stamp_report"):
		_on_stamp(Judge.STAMP_REPORT)
