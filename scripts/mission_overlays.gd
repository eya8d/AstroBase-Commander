## scripts/mission_overlays.gd
## FINAL EVALUATION: opened by the closing transmission (StoryDialog -> EventBus.mission_over).
##
## Shows the ending (Mission Accomplished / Mission Survived / Mission Paused, from
## data/ending_rules.json -> story_endings), the score per category and the total out of
## 1000 (Mission.compute_evaluation), every decision with its consequence, the NASA
## insights with their sources, achievements, the final stores (ui/victory.json /
## ui/defeat.json stats) and the learning tips for the failure cause.
## The painted mission_complete / mission_failed screens are kept as the backdrop.
extends Node

const COMPLETE_ART := "res://assets/ui/screens/mission_complete.png"
const FAILED_ART := "res://assets/ui/screens/mission_failed.png"
const TEXT := Color(0.95, 0.92, 0.88)
const MUTED := Color(0.66, 0.63, 0.6)
const ACCENT := Color(1.0, 0.62, 0.3)
const GOOD := Color(0.5, 1.0, 0.6)
const WARN := Color(1.0, 0.8, 0.35)
const BAD := Color(1.0, 0.42, 0.38)
const ENDING_COLORS: Dictionary = {
	"mission_accomplished": Color(0.5, 1.0, 0.6), "mission_survived": Color(1.0, 0.8, 0.35),
	"mission_paused": Color(1.0, 0.42, 0.38),
}
const CATEGORY_NAMES: Dictionary = {
	"resources": "Resources", "safety": "Safety", "wellbeing": "Well-being",
	"science": "Science", "infrastructure": "Infrastructure",
}

var _root: Control
var _art: TextureRect
var _content: Control
var _tab_body: VBoxContainer
var _tab_buttons: Dictionary = {}
var _result_open: bool = false
var _state: String = ""
var _reason: String = ""


func _ready() -> void:
	# Must stay alive while the tree is paused by the report.
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.name = "MissionCanvas"
	layer.layer = 25
	add_child(layer)
	_root = Control.new()
	_root.name = "ResultRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	layer.add_child(_root)
	_art = UiRegions.add_fullscreen_art(_root, null, "ResultArt")
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.015, 0.02, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	EventBus.mission_over.connect(_show)


func is_open() -> bool:
	return _result_open


# ==================== helpers ====================

func _box(bg: Color, border: Color, border_w: int, radius: int, margin: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s


func _label(font_size: int, color: Color, wrap: bool = false) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _button(text: String, accent: Color, min_w: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(min_w, 40)
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", accent)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_stylebox_override("normal", _box(Color(0.1, 0.08, 0.09), accent.darkened(0.3), 1, 4, 8))
	b.add_theme_stylebox_override("hover", _box(Color(0.2, 0.12, 0.08), accent, 2, 4, 8))
	b.add_theme_stylebox_override("pressed", _box(Color(0.28, 0.15, 0.08), accent, 2, 4, 8))
	b.mouse_entered.connect(AudioManager.play_ui_hover)
	return b


func _score_color(score: int) -> Color:
	if score >= 70:
		return GOOD
	if score >= 50:
		return WARN
	return BAD


# ==================== report ====================

func _show(state: String, reason: String) -> void:
	if state.is_empty():
		_hide()
		return
	_state = state
	_reason = reason
	if Mission.evaluation.is_empty():
		Mission.evaluation = Mission.compute_evaluation(state == "complete")
	var report: Dictionary = Mission.evaluation
	var ending: Dictionary = report.get("ending", Mission.ending)
	var ending_id: String = str(ending.get("id", "mission_paused" if state != "complete" else "mission_survived"))
	var color: Color = ENDING_COLORS.get(ending_id, ACCENT)
	var screen: Dictionary = DataLoader.get_ui_screen("victory" if state == "complete" else "defeat")

	_art.texture = load(COMPLETE_ART if state == "complete" else FAILED_ART) as Texture2D
	if _content != null:
		_content.queue_free()
	_root.visible = true
	_result_open = true
	get_tree().paused = true

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Color(0.045, 0.035, 0.05, 0.96), color.lerp(ACCENT, 0.3), 2, 6, 14))
	panel.position = Vector2(30, 18)
	panel.custom_minimum_size = Vector2(1220, 684)
	panel.size = Vector2(1220, 684)
	_root.add_child(panel)
	_content = panel
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 10)
	panel.add_child(main)

	# --- header ---
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	main.add_child(header)
	var head_col := VBoxContainer.new()
	head_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_col.add_theme_constant_override("separation", 2)
	header.add_child(head_col)
	var kicker := _label(13, ACCENT)
	kicker.text = "FINAL EVALUATION  ·  %s  ·  %s  ·  %s DIFFICULTY" % [
		str(GameState.get_scenario().get("title", "")).to_upper(), GameState.get_landing_site_name().to_upper(),
		GameState.difficulty.to_upper()]
	head_col.add_child(kicker)
	var title := _label(36, color)
	title.text = str(ending.get("title", screen.get("title", "MISSION REPORT")))
	head_col.add_child(title)
	var text := _label(14, TEXT, true)
	text.text = str(ending.get("text", ""))
	head_col.add_child(text)
	var survived: int = int(report.get("completed_sol", Mission.completed_sols))
	var sub := _label(13, MUTED, true)
	if state == "complete":
		sub.text = "All %d Sols completed. %s" % [GameState.target_sols - GameState.get_start_sol() + 1,
			"Every decision below was logged by NOVA."]
	else:
		var tips_key: String = Mission.loss_resource()
		sub.text = "Paused on Sol %d: %s. Sols completed: %d of %d." % [Mission.sol, reason,
			maxi(0, survived - GameState.get_start_sol() + 1), GameState.target_sols - GameState.get_start_sol() + 1]
		if not tips_key.is_empty():
			sub.text += "  %s ran out." % ResourceManager.get_display_name(tips_key)
	head_col.add_child(sub)

	var score_box := PanelContainer.new()
	score_box.add_theme_stylebox_override("panel", _box(Color(0.08, 0.06, 0.06), color, 2, 6, 10))
	score_box.custom_minimum_size = Vector2(220, 0)
	header.add_child(score_box)
	var score_col := VBoxContainer.new()
	score_col.alignment = BoxContainer.ALIGNMENT_CENTER
	score_box.add_child(score_col)
	var score_cap := _label(13, MUTED)
	score_cap.text = "TOTAL SCORE"
	score_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_col.add_child(score_cap)
	var score_v := _label(40, color)
	score_v.text = "%d" % int(report.get("total", 0))
	score_v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_col.add_child(score_v)
	var score_max := _label(13, MUTED)
	score_max.text = "out of %d" % int(report.get("total_max", 1000))
	score_max.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_col.add_child(score_max)

	# --- body ---
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	main.add_child(body)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(500, 0)
	left.add_theme_constant_override("separation", 6)
	body.add_child(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	body.add_child(right)

	var cat_head := _label(13, ACCENT)
	cat_head.text = "EVALUATION BY CATEGORY"
	left.add_child(cat_head)
	for c: Variant in report.get("categories", []):
		_category_row(left, c)

	var stats_head := _label(13, ACCENT)
	stats_head.text = "FINAL STATE OF THE BASE"
	left.add_child(stats_head)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 2)
	left.add_child(grid)
	for st: Variant in screen.get("stats", []):
		if not st is Dictionary:
			continue
		var row: Dictionary = st
		var res: String = str(row.get("resource_id", ""))
		if res.is_empty():
			continue
		var cell := _label(12, TEXT)
		cell.text = "%s: %d" % [str(row.get("label", res)), ResourceManager.get_amount(res)]
		grid.add_child(cell)
	for res2: String in ["crew_health", "crew_morale", "base_integrity"]:
		var cell2 := _label(12, TEXT)
		cell2.text = "%s: %d" % [ResourceManager.get_display_name(res2), ResourceManager.get_amount(res2)]
		grid.add_child(cell2)
	var extra := _label(12, MUTED, true)
	extra.text = "Decisions logged: %d  ·  Sols with a supply under 30%%: %d  ·  Science target: %d" % [
		Mission.decisions.size(), int(report.get("shortage_sols", 0)), Mission.get_science_target()]
	left.add_child(extra)

	# --- right: tabs ---
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	right.add_child(tabs)
	for spec: Array in [["decisions", "DECISION LOG"], ["insights", "NASA INSIGHTS & LESSONS"], ["sources", "DATA SOURCES"]]:
		var tb := _button(str(spec[1]), Color(0.55, 0.85, 1.0))
		tb.custom_minimum_size = Vector2(0, 32)
		tb.add_theme_font_size_override("font_size", 13)
		tb.pressed.connect(_show_tab.bind(str(spec[0])))
		tabs.add_child(tb)
		_tab_buttons[str(spec[0])] = tb
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var scroll_box := PanelContainer.new()
	scroll_box.add_theme_stylebox_override("panel", _box(Color(0.03, 0.03, 0.045, 0.9), Color(0.3, 0.5, 0.6, 0.45), 1, 4, 8))
	scroll_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_box.add_child(scroll)
	right.add_child(scroll_box)
	_tab_body = VBoxContainer.new()
	_tab_body.custom_minimum_size = Vector2(640, 0)
	_tab_body.add_theme_constant_override("separation", 6)
	scroll.add_child(_tab_body)

	# --- buttons from ui/victory.json / ui/defeat.json ---
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 16)
	main.add_child(footer)
	for b: Variant in screen.get("buttons", []):
		if not b is Dictionary:
			continue
		var spec_b: Dictionary = b
		var action: String = str(spec_b.get("action", ""))
		var btn := _button(str(spec_b.get("label", action)), GOOD if action == "restart_game" else ACCENT, 240)
		match action:
			"restart_game":
				btn.pressed.connect(_retry)
			"open_data_sources":
				btn.pressed.connect(_show_tab.bind("sources"))
			"go_to_main_menu":
				btn.pressed.connect(_to_menu)
			_:
				btn.disabled = true
		footer.add_child(btn)
	_show_tab("decisions")


func _category_row(parent: VBoxContainer, c: Variant) -> void:
	if not c is Dictionary:
		return
	var cat: Dictionary = c
	var score: int = int(cat.get("score", 0))
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 1)
	var top := HBoxContainer.new()
	var name_l := _label(14, TEXT)
	name_l.text = str(cat.get("name", ""))
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_l)
	var pts: int = int(cat.get("points", 0))
	var pts_l := _label(12, GOOD if pts > 0 else (BAD if pts < 0 else MUTED))
	pts_l.text = "decisions %+d   " % pts
	top.add_child(pts_l)
	var score_l := _label(14, _score_color(score))
	score_l.text = "%d / 100" % score
	top.add_child(score_l)
	row.add_child(top)
	var track := ColorRect.new()
	track.color = Color(0.15, 0.12, 0.13)
	track.custom_minimum_size = Vector2(500, 8)
	var fill := ColorRect.new()
	fill.color = _score_color(score)
	fill.size = Vector2(500.0 * clampf(float(score) / 100.0, 0.0, 1.0), 8)
	track.add_child(fill)
	row.add_child(track)
	var covers := _label(11, MUTED)
	covers.text = str(cat.get("covers", ""))
	row.add_child(covers)
	parent.add_child(row)


func _show_tab(tab: String) -> void:
	AudioManager.play_ui_confirm()
	for key: String in _tab_buttons:
		var b: Button = _tab_buttons[key]
		b.add_theme_color_override("font_color", Color.WHITE if key == tab else Color(0.55, 0.85, 1.0))
	for child: Node in _tab_body.get_children():
		_tab_body.remove_child(child)
		child.queue_free()
	match tab:
		"decisions":
			_fill_decisions()
		"insights":
			_fill_insights()
		"sources":
			_fill_sources()


func _add(text: String, size: int, color: Color) -> void:
	var l := _label(size, color, true)
	l.text = text
	_tab_body.add_child(l)


func _fill_decisions() -> void:
	if Mission.decisions.is_empty():
		_add("No decisions were logged in this run.", 13, MUTED)
		return
	for d: Variant in Mission.decisions:
		if not d is Dictionary:
			continue
		var row: Dictionary = d
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 1)
		var head := _label(13, ACCENT, true)
		head.text = "SOL %02d  ·  %s%s" % [int(row.get("sol", 0)), str(row.get("title", "")).to_upper(),
			"  (EMERGENCY)" if str(row.get("kind", "")) == "event" else ""]
		box.add_child(head)
		var choice := _label(13, TEXT, true)
		choice.text = "Decision: %s" % str(row.get("label", ""))
		box.add_child(choice)
		var cons := _label(12, Color(0.8, 0.77, 0.73), true)
		cons.text = str(row.get("consequence", ""))
		box.add_child(cons)
		var scores: Dictionary = row.get("scores", {})
		if not scores.is_empty():
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 12)
			for key: String in scores:
				var v: int = int(scores[key])
				var s := _label(11, GOOD if v > 0 else (BAD if v < 0 else MUTED))
				s.text = "%s %+d" % [str(CATEGORY_NAMES.get(key, key)), v]
				line.add_child(s)
			box.add_child(line)
		var sep := ColorRect.new()
		sep.color = Color(1.0, 0.55, 0.25, 0.15)
		sep.custom_minimum_size = Vector2(0, 1)
		box.add_child(sep)
		_tab_body.add_child(box)


func _fill_insights() -> void:
	var story_eval: Variant = Mission.story.get("evaluation", {})
	if story_eval is Dictionary:
		_add("WHAT THE MISSION TAUGHT (real NASA findings)", 13, ACCENT)
		for i: Variant in (story_eval as Dictionary).get("insights", []):
			if not i is Dictionary:
				continue
			var ins: Dictionary = i
			_add("•  %s" % str(ins.get("text", "")), 13, TEXT)
			var src: Dictionary = DataLoader.get_data_source(str(ins.get("source_id", "")))
			if not src.is_empty():
				_add("    %s · %s  %s" % [str(src.get("organization", "")), str(src.get("title", "")), str(src.get("url", ""))], 11, Color(0.55, 0.62, 0.7))
	var screen: Dictionary = DataLoader.get_ui_screen("victory")
	_add("MISSION LESSONS", 13, ACCENT)
	for line: Variant in screen.get("education", []):
		_add("•  %s" % str(line), 13, TEXT)
	if _state != "complete":
		var tips: Dictionary = DataLoader.get_ui_screen("defeat").get("learning_tips_by_failure", {})
		var key: String = Mission.loss_resource()
		var list: Variant = tips.get(key, [])
		if list is Array and not (list as Array).is_empty():
			_add("WHAT TO TRY NEXT TIME (%s)" % _reason, 13, BAD)
			for tip: Variant in list:
				_add("•  %s" % str(tip), 13, TEXT)
	_add("ACHIEVEMENTS", 13, ACCENT)
	if Mission.achievements_unlocked.is_empty():
		_add("None unlocked in this run.", 12, MUTED)
	for a: Variant in DataLoader.get_achievements():
		if a is Dictionary and Mission.achievements_unlocked.has(str((a as Dictionary).get("id", ""))):
			_add(">  %s: %s" % [str(a.get("name", "")), str(a.get("description", ""))], 13, GOOD)
	_add("Score values, resource amounts and event damage are game balance, not NASA data.", 11, MUTED)


func _fill_sources() -> void:
	_add("DATA SOURCES USED BY THE GAME (data/data_sources.json)", 13, ACCENT)
	for s: Variant in DataLoader.get_data_sources():
		if not s is Dictionary:
			continue
		var src: Dictionary = s
		_add("%s  ·  %s" % [str(src.get("organization", "")), str(src.get("title", src.get("id", "")))], 13, TEXT)
		var used_raw: Variant = src.get("used_for", [])
		var used: String = str(used_raw)
		if used_raw is Array:
			used = ", ".join(PackedStringArray(used_raw)).replace("_", " ")
		if not used.is_empty():
			_add("    Used for: %s" % used, 11, MUTED)
		_add("    %s" % str(src.get("url", "")), 11, Color(0.55, 0.62, 0.7))


func _hide() -> void:
	_result_open = false
	_root.visible = false
	get_tree().paused = false


func _retry() -> void:
	AudioManager.play_ui_confirm()
	get_tree().paused = false
	GameState.begin_mission()
	get_tree().reload_current_scene()


func _to_menu() -> void:
	AudioManager.play_ui_back()
	get_tree().paused = false
	GameState.mission_running = false
	get_tree().change_scene_to_file("res://scenes/menu_main.tscn")
