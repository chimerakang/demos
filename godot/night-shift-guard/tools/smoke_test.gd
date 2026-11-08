extends Node
## 無頭冒煙測試：不開 UI，直接驅動 NightController 跑完第 1、2 晚，
## 故意犯幾個錯（放活人、仇家同層），確認後果鏈沒有崩。
##
## 執行：godot --headless --path . tools/smoke_test.tscn

var fails := 0


func _ready() -> void:
	_run()
	get_tree().quit(1 if fails > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  ✓ ", msg)
	else:
		fails += 1
		printerr("  ✗ ", msg)


func _run() -> void:
	print("== DataLoader ==")
	_check(DataLoader.load_errors.is_empty(), "載入無錯誤 %s" % str(DataLoader.load_errors))
	_check(DataLoader.applicants.size() >= 19, "登記者池 %d 位" % DataLoader.applicants.size())
	_check(DataLoader.rules.size() == 12, "規則 %d 條" % DataLoader.rules.size())
	_check(DataLoader.nights.size() == 7, "七晚時程")

	GameState.reset_all()
	var night := NightController.new()
	add_child(night)

	# ── 第 1 晚：全部正確 ──
	print("== 第 1 晚（全對）==")
	night.start_night()
	_check(night.active_rules.size() == 1, "第 1 晚只有 1 條規則生效（實際 %d）" % night.active_rules.size())
	night.open_desk()
	var room := 0
	while night.current != null:
		var a := night.current
		if a.should_be_admitted():
			GameState.place(a, 0, room % 3)
			room += 1
			night.stamp(Judge.STAMP_APPROVE)
		else:
			night.stamp(Judge.STAMP_DENY)
	_check(GameState.wrong_count == 0, "第 1 晚 0 錯（實際 %d）" % GameState.wrong_count)
	_check(GameState.correct_count == 6, "第 1 晚 6 對（實際 %d）" % GameState.correct_count)
	_check(GameState.axis.has("chen_bo") and GameState.axis["chen_bo"] == -20, "陳伯初始軸 −20")
	night.end_day()
	_check(GameState.night == 2, "進到第 2 晚")
	_check(GameState.debt == 300000 - 6 * 1500, "債務扣薪 %d" % GameState.debt)

	# ── 第 2 晚：故意放一個活人 + 把阿凱與貨車司機排同層 ──
	print("== 第 2 晚（故意犯錯）==")
	GameState.reset_all()
	GameState.night = 2
	night.pending_returns.clear()
	night.start_night()
	_check(night.active_rules.size() == 3, "第 2 晚 3 條規則生效（實際 %d）" % night.active_rules.size())
	night.open_desk()
	var placed_hostile := 0
	while night.current != null:
		var a := night.current
		match a.id:
			"h_grief_mother":
				# 故意放活人進來
				GameState.place(a, 2, 0)
				night.stamp(Judge.STAMP_APPROVE)
			"g_truck_driver", "g_street_youth":
				GameState.place(a, 1, placed_hostile)
				placed_hostile += 1
				night.stamp(Judge.STAMP_APPROVE)
			_:
				if a.should_be_admitted():
					var slot: int = GameState.find_free_slot_for_test(0)
					if slot != -1:
						GameState.place(a, 0, slot)
					night.stamp(Judge.STAMP_APPROVE)
				else:
					night.stamp(Judge.STAMP_DENY)
	_check(GameState.wrong_count == 1, "第 2 晚 1 錯（實際 %d）" % GameState.wrong_count)
	_check(GameState.strikes == 1, "記點 1（實際 %d）" % GameState.strikes)
	# 第 2 晚沒有 g_street_youth（他在第 1 晚），所以相沖不會觸發——改成直接呼叫 RoomTable 驗證
	var youth: Applicant = DataLoader.get_applicant("g_street_youth")
	var truck: Applicant = DataLoader.get_applicant("g_truck_driver")
	var rule: Rule = DataLoader.rules.filter(func(r): return r.check_id == "same_incident")[0]
	# 注意：同一事故規則要求 death_date 相同；資料裡阿凱 11-01、司機死亡證明寫 11-02 但 death_date 欄位 11-01
	var hit := RoomTable.conflict_fires(rule, youth, truck)
	_check(not hit.is_empty(), "阿凱 × 貨車司機 命中 same_incident：%s" % hit.get("text", ""))
	_check(GameState.known_relation("g_street_youth", "g_truck_driver") == "" , "尚未寫進筆記本（事件未在結算發生）")
	var ret_ok := night.pending_returns.has("")
	_check(not ret_ok, "林淑芬 return_as 為空，不會隔晚回來")

	# ── 判定引擎直接測 ──
	print("== Judge ==")
	var rules_n2: Array[Rule] = DataLoader.rules_active_on(2)
	var debtor: Applicant = DataLoader.get_applicant("h_lin_debtor")
	var v := Judge.evaluate(debtor, Judge.STAMP_APPROVE, rules_n2)
	_check(not v["correct"] and v["missed_checks"].has("has_death_cert") and v["missed_checks"].has("id_cancelled"),
		"放活人 → 錯，漏了 %s" % str(v["missed_checks"]))
	var runner: Applicant = DataLoader.get_applicant("h_debt_runner")
	v = Judge.evaluate(runner, Judge.STAMP_REPORT, DataLoader.rules_active_on(6))
	_check(v["correct"], "假冒者通報 → 對")
	_check(Judge.available_tells(runner, DataLoader.rules_active_on(6)).has("forged_document"), "第 6 晚能抓到偽造文件")
	_check(not Judge.available_tells(runner, DataLoader.rules_active_on(1)).has("forged_document"), "第 1 晚抓不到偽造文件")
	var insp: Applicant = DataLoader.get_applicant("inspector")
	_check(Judge.evaluate(insp, Judge.STAMP_APPROVE, rules_n2)["correct"], "抽查員放行 → 對")
	_check(not Judge.evaluate(insp, Judge.STAMP_DENY, rules_n2)["correct"], "抽查員拒絕 → 錯")

	# ── 生肖 ──
	print("== RoomTable 生肖 ==")
	var zr: Rule = DataLoader.rules.filter(func(r): return r.check_id == "zodiac_clash")[0]
	var mouse: Applicant = DataLoader.get_applicant("g_old_teacher")   # 鼠
	var horse: Applicant = DataLoader.get_applicant("lin_son")          # 馬
	_check(not RoomTable.conflict_fires(zr, mouse, horse).is_empty(), "鼠 × 馬 相沖")
	_check(RoomTable.conflict_fires(zr, mouse, mouse).is_empty(), "鼠 × 鼠 不沖")

	# ── 存檔 ──
	print("== 存檔 ==")
	GameState.note_relation("a", "b", "hostile")
	GameState.save()
	var n_before: int = GameState.night
	GameState.night = 99
	_check(GameState.load_save(), "讀檔成功")
	_check(GameState.night == n_before, "讀回 night=%d" % GameState.night)
	_check(GameState.known_relation("b", "a") == "hostile", "筆記本關係無序 key 正常")

	print("\n%s：%d 個失敗" % ["FAIL" if fails > 0 else "PASS", fails])
