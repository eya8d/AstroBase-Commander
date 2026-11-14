## scripts/story_dialog.gd
## Mission cards on top of the base: the 30-Sol story days (data/story/campaign_30_sols.json),
## random and scripted emergencies (data/events.json), the training-scenario briefing and
## the closing transmission that opens the Final Evaluation.
##
## Every number comes from the Mission rules (scripts/mission.gd); this layer only shows the
## card, types the NOVA / Layla / Commander lines, and hands the chosen option back.
## While a card is open the game is paused (the Sol clock stops).
extends CanvasLayer

const STORY_PATH := "res://data/story/campaign_30_sols.json"
const ALERT_COLORS: Dictionary = {
	"green": Color("7CFF8A"), "yellow": Color("FFD24A"), "orange": Color("FF8C3A"),
	"red": Color("FF4A3A"), "blue": Color("6FC8FF"),
}
const ALERT_TEXT: Dictionary = {
	"green": "STATUS GREEN", "yellow": "YELLOW ALERT", "orange": "ORANGE ALERT",
	"red": "RED ALERT", "blue": "TRAINING",
}
const SEVERITY_ALERT: Dictionary = {"low": "yellow", "medium": "orange", "high": "red"}
const DEFAULT_SPEAKERS: Dictionary = {
	"NOVA": {"name": "NOVA", "role": "Base AI", "color": "#7FE3FF"},
	"LAYLA": {"name": "Layla", "role": "Earth Control Center", "color": "#9CF08A"},
	"PLAYER": {"name": "Commander", "role": "You", "color": "#FFB45C"},
	"LOG": {"name": "Mission Log", "role": "", "color": "#C9C2B8"},
}
const STATUS_ROWS: Array = [
	["energy", "ENERGY", Color(1.0, 0.82, 0.3)], ["oxygen", "OXYGEN", Color(0.35, 0.85, 1.0)],
	["water", "WATER", Color(0.4, 0.6, 1.0)], ["food", "FOOD", Color(0.55, 0.95, 0.45)],
	["shield", "SHIELD", Color(0.75, 0.55, 1.0)], ["crew_health", "CREW HEALTH", Color(1.0, 0.5, 0.55)],
	["crew_morale", "MORALE", Color(1.0, 0.75, 0.4)], ["base_integrity", "INTEGRITY", Color(0.82, 0.82, 0.88)],
	["science", "SCIENCE", Color(0.85, 0.65, 1.0)],
]
const CHARS_PER_SECOND := 80.0
const PANEL_RECT := Rect2(40, 28, 1200, 664)
const LEFT_W := 760.0
const RIGHT_W := 386.0
const TEXT := Color(0.95, 0.92, 0.88)
const MUTED := Color(0.68, 0.65, 0.62)
const ACCENT := Color(1.0, 0.62, 0.3)

var _speakers: Dictionary = DEFAULT_SPEAKERS.duplicate(true)
var _card: Dictionary = {}
var _local_cards: Array = []
var _briefed: bool = false
var _lines: Array = []
var _line_index: int = -1
var _typing: bool = false
var _typed: float = 0.0
var _chars_from: int = 0
var _chars_to: int = 0
var _choices_shown: bool = false
var _result_shown: bool = false
var _history_open: bool = false
var _pick_list: Array = []         # [Callable] for the 1-4 keys
var _paused_by_me: bool = false

var _root: Control
var _panel_style: StyleBoxFlat
var _kicker: Label
var _title: Label
var _location: Label
var _alert_style: StyleBoxFlat
var _alert_label: Label
var _delay_label: Label
var _scene_label: Label
var _dialogue: RichTextLabel
var _choices: VBoxContainer
var _footer: Label
var _next_button: Button
var _skip_button: Button
var _status_rows: Dictionary = {}
var _context: VBoxContainer
var _history_button: Button


## Small line chart of the supply stores over the logged Sols.
class HistoryGraph extends Control:
	var rows: Array = []
	var series: Array = [
		["energy", Color(1.0, 0.82, 0.3)], ["oxygen", Color(0.35, 0.85, 1.0)],
		["water", Color(0.4, 0.6, 1.0)], ["food", Color(0.55, 0.95, 0.45)],
	]

	func _draw() -> void:
		var area := Rect2(Vector2.ZERO, size)
		draw_rect(area, Color(0.03, 0.03, 0.05, 0.95))
		draw_rect(area, Color(0.45, 0.45, 0.55, 0.6), false, 1.0)
		for i: int in range(1, 4):
			var gy: float = size.y * float(i) / 4.0
			draw_line(Vector2(1, gy), Vector2(size.x - 1, gy), Color(0.3, 0.3, 0.38, 0.35), 1.0)
		if rows.size() < 2:
			draw_string(ThemeDB.fallback_font, Vector2(10, size.y * 0.5), "Not enough Sols logged yet.",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.7, 0.7))
			return
		var top: float = 1.0
		for row: Variant in rows:
			for s: Variant in series:
				top = maxf(top, float((row as Dictionary).get(str(s[0]), 0)))
		for s: Variant in series:
			var pts := PackedVector2Array()
			for i: int in rows.size():
				var x: float = 6.0 + (size.x - 12.0) * float(i) / float(rows.size() - 1)
				var v: float = float((rows[i] as Dictionary).get(str(s[0]), 0))
				pts.append(Vector2(x, size.y - 6.0 - (size.y - 12.0) * v / top))
			draw_polyline(pts, s[1], 2.0)


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	var story: Dictionary = DataLoader.get_story(STORY_PATH)
	var sp: Variant = story.get("speakers", {})
	if sp is Dictionary:
		for key: String in sp:
			_speakers[key] = sp[key]
	_build_ui()
	_root.visible = false
	Mission.cards_ready.connect(_on_cards_ready)
	Mission.sol_started.connect(_on_sol_started)
	ResourceManager.resource_changed.connect(_on_resource_changed)


func _on_resource_changed(_type: String, _total: int) -> void:
	if is_open():
		_refresh_status()


func is_open() -> bool:
	return _root != null and _root.visible


# ==================== construction ====================

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


func _button(text: String, accent: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", accent)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_stylebox_override("normal", _box(Color(0.1, 0.08, 0.09), accent.darkened(0.3), 1, 4, 8))
	b.add_theme_stylebox_override("hover", _box(Color(0.2, 0.12, 0.08), accent, 2, 4, 8))
	b.add_theme_stylebox_override("pressed", _box(Color(0.28, 0.15, 0.08), accent, 2, 4, 8))
	b.add_theme_stylebox_override("disabled", _box(Color(0.07, 0.07, 0.08), Color(0.3, 0.3, 0.33), 1, 4, 8))
	b.mouse_entered.connect(AudioManager.play_ui_hover)
	return b


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "StoryRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.02, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	var panel := PanelContainer.new()
	_panel_style = _box(Color(0.05, 0.04, 0.055, 0.97), ACCENT, 2, 6, 14)
	panel.add_theme_stylebox_override("panel", _panel_style)
	panel.position = PANEL_RECT.position
	panel.size = PANEL_RECT.size
	panel.custom_minimum_size = PANEL_RECT.size
	_root.add_child(panel)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	panel.add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(LEFT_W, 0)
	left.add_theme_constant_override("separation", 6)
	columns.add_child(left)
	var rule := ColorRect.new()
	rule.color = Color(1.0, 0.55, 0.25, 0.3)
	rule.custom_minimum_size = Vector2(2, 0)
	columns.add_child(rule)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(RIGHT_W, 0)
	right.add_theme_constant_override("separation", 6)
	columns.add_child(right)

	# --- header ---
	var header := HBoxContainer.new()
	left.add_child(header)
	var head_col := VBoxContainer.new()
	head_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_col.add_theme_constant_override("separation", 0)
	header.add_child(head_col)
	_kicker = _label(13, ACCENT)
	head_col.add_child(_kicker)
	_title = _label(26, TEXT)
	head_col.add_child(_title)
	_location = _label(13, MUTED)
	head_col.add_child(_location)
	var badge_col := VBoxContainer.new()
	badge_col.add_theme_constant_override("separation", 4)
	header.add_child(badge_col)
	var badge := PanelContainer.new()
	_alert_style = _box(ACCENT, ACCENT, 0, 4, 6)
	badge.add_theme_stylebox_override("panel", _alert_style)
	_alert_label = _label(13, Color(0.08, 0.05, 0.04))
	_alert_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_alert_label.custom_minimum_size = Vector2(150, 0)
	badge.add_child(_alert_label)
	badge_col.add_child(badge)
	_delay_label = _label(12, Color(0.6, 0.85, 1.0))
	_delay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge_col.add_child(_delay_label)

	_scene_label = _label(14, Color(0.8, 0.74, 0.68), true)
	left.add_child(_scene_label)

	# --- dialogue ---
	var dbox := PanelContainer.new()
	dbox.add_theme_stylebox_override("panel", _box(Color(0.025, 0.025, 0.04, 0.95), Color(0.3, 0.5, 0.6, 0.5), 1, 4, 10))
	dbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(dbox)
	_dialogue = RichTextLabel.new()
	_dialogue.bbcode_enabled = true
	_dialogue.scroll_following = true
	_dialogue.custom_minimum_size = Vector2(0, 110)
	_dialogue.add_theme_font_size_override("normal_font_size", 16)
	_dialogue.add_theme_font_size_override("bold_font_size", 16)
	_dialogue.add_theme_font_size_override("italics_font_size", 15)
	_dialogue.add_theme_constant_override("line_separation", 3)
	_dialogue.gui_input.connect(_on_dialogue_input)
	dbox.add_child(_dialogue)

	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 6)
	left.add_child(_choices)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	left.add_child(footer)
	_footer = _label(12, MUTED)
	_footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_footer)
	_skip_button = _button("SHOW ALL", MUTED)
	_skip_button.pressed.connect(_skip_lines)
	footer.add_child(_skip_button)
	_next_button = _button("NEXT  >", ACCENT)
	_next_button.pressed.connect(_advance)
	footer.add_child(_next_button)

	# --- right column: live base status + context ---
	var status_title := _label(13, ACCENT)
	status_title.text = "BASE STATUS"
	right.add_child(status_title)
	for spec: Array in STATUS_ROWS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var name_l := _label(12, Color(0.82, 0.8, 0.76))
		name_l.text = str(spec[1])
		name_l.custom_minimum_size = Vector2(96, 0)
		row.add_child(name_l)
		var track := ColorRect.new()
		track.color = Color(0.15, 0.12, 0.13)
		track.custom_minimum_size = Vector2(190, 10)
		track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := ColorRect.new()
		fill.color = spec[2]
		fill.size = Vector2(0, 10)
		track.add_child(fill)
		row.add_child(track)
		var value_l := _label(12, TEXT)
		value_l.custom_minimum_size = Vector2(78, 0)
		value_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value_l)
		right.add_child(row)
		_status_rows[str(spec[0])] = {"fill": fill, "value": value_l, "color": spec[2]}

	var sep := ColorRect.new()
	sep.color = Color(1.0, 0.55, 0.25, 0.25)
	sep.custom_minimum_size = Vector2(0, 1)
	right.add_child(sep)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_context = VBoxContainer.new()
	_context.custom_minimum_size = Vector2(RIGHT_W - 14, 0)
	_context.add_theme_constant_override("separation", 5)
	scroll.add_child(_context)
	_history_button = _button("VIEW HISTORICAL DATA", Color(0.55, 0.85, 1.0))
	_history_button.pressed.connect(_toggle_history)
	right.add_child(_history_button)


# ==================== card flow ====================

func _on_sol_started(number: int) -> void:
	if GameState.is_story_campaign() or _briefed or number != GameState.get_start_sol():
		return
	_briefed = true
	_local_cards.append({"kind": "briefing"})
	if not is_open():
		_show_next()


func _on_cards_ready() -> void:
	if not is_open():
		_show_next()


func _next_card() -> Dictionary:
	if not _local_cards.is_empty():
		return _local_cards.pop_front()
	return Mission.pop_card()


func _show_next() -> void:
	var card: Dictionary = _next_card()
	if card.is_empty():
		_close(true)
		return
	_open(card)


func _open(card: Dictionary) -> void:
	_card = card
	_root.visible = true
	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_me = true
	AudioManager.play_interface_zoom()
	_choices_shown = false
	_result_shown = false
	_history_open = false
	_typing = false
	_pick_list.clear()
	_clear(_choices)
	_dialogue.clear()
	_dialogue.visible_characters = -1
	_history_button.visible = false
	_history_button.text = "VIEW HISTORICAL DATA"
	_delay_label.text = ""
	_lines = []
	match str(card.get("kind", "")):
		"story":
			_setup_story()
		"event":
			_setup_event()
		"final":
			_setup_final()
		"briefing":
			_setup_briefing()
	_refresh_status()
	_line_index = -1
	_skip_button.visible = _lines.size() > 1
	_next_button.visible = true
	_advance()


func _close(unpause: bool) -> void:
	_root.visible = false
	_card = {}
	if unpause and _paused_by_me:
		get_tree().paused = false
	_paused_by_me = false


func _set_alert(alert: String) -> void:
	var color: Color = ALERT_COLORS.get(alert, ACCENT)
	_alert_style.bg_color = color
	_alert_label.text = str(ALERT_TEXT.get(alert, alert.to_upper()))
	_panel_style.border_color = color.lerp(ACCENT, 0.35)


func _filter_lines(raw: Variant) -> Array:
	var out: Array = []
	if raw is Array:
		for line: Variant in raw:
			if line is Dictionary and Mission.condition_ok(line):
				out.append(line)
	return out


func _week_text() -> String:
	var week: Dictionary = Mission.get_week()
	if week.is_empty():
		return ""
	return "  ·  WEEK %d: %s" % [int(week.get("week", 0)), str(week.get("title", "")).to_upper()]


func _setup_story() -> void:
	var day: Dictionary = _card.get("day", {})
	_kicker.text = "SOL %02d / %d%s" % [int(day.get("day", Mission.sol)), GameState.target_sols, _week_text()]
	_title.text = str(day.get("title", "")).to_upper()
	_location.text = "LOCATION: %s" % str(day.get("location", "Base"))
	_set_alert(str(day.get("alert", "green")))
	var delay: int = int(day.get("comm_delay_minutes", 0))
	if delay > 0:
		_delay_label.text = "EARTH SIGNAL DELAY: %d MIN" % delay
	_scene_label.text = Mission.format_text(str(day.get("scene", "")))
	_lines = _filter_lines(day.get("dialogue", []))
	var summary: String = str(day.get("summary", ""))
	var inst: Dictionary = _card.get("event", {})
	match summary:
		"week":
			_ctx_week()
		"history":
			_ctx_history()
		"science":
			_ctx_science()
		"faults":
			_ctx_faults()
		_:
			if not inst.is_empty():
				_ctx_event(inst)
			else:
				_ctx_default()
	_history_button.visible = not str(day.get("historical_ref", "")).is_empty()


func _setup_event() -> void:
	var inst: Dictionary = _card.get("event", {})
	var def: Dictionary = inst.get("def", {})
	_kicker.text = "SOL %02d / %d  ·  UNSCHEDULED EMERGENCY" % [Mission.sol, GameState.target_sols]
	_title.text = str(def.get("name", "Emergency")).to_upper()
	_location.text = "CATEGORY: %s  ·  SEVERITY: %s  ·  LASTS %d SOL" % [
		str(def.get("category", "")).replace("_", " ").to_upper(), str(def.get("severity", "")).to_upper(),
		int(def.get("duration_sols", 1))]
	_set_alert(str(SEVERITY_ALERT.get(str(def.get("severity", "medium")), "orange")))
	var impact: String = _effects_text(def.get("effects", []), false)
	_scene_label.text = "Immediate impact: %s." % impact if not impact.is_empty() else "NOVA has flagged a new hazard."
	_lines = [{"speaker": "NOVA", "text": "Alert! %s detected. %s" % [str(def.get("name", "")),
		("The base has already taken the hit: %s." % impact) if not impact.is_empty() else "Response options are ready."]}]
	if Mission.is_radiation_event(def):
		var req: Dictionary = Mission.radiation_requirements(inst)
		_lines.append({"speaker": "NOVA", "text": "To raise the shield I need the shield generator online, %d energy and %d shield points. Unprotected, the crew loses %d health." % [
			int(req["energy"]), int(req["shield"]), Mission.radiation_penalty(inst)]})
	if not str(inst.get("historical_ref", "")).is_empty():
		_lines.append({"speaker": "LOG", "text": "Training scenario based on the archived NASA DONKI SEP event of September 2017. This is historical data, not a live alert."})
		_history_button.visible = true
	_lines.append({"speaker": "LAYLA", "text": "Pick a response, Commander. Every option has a cost; doing nothing has one too."})
	_ctx_event(inst)


func _setup_final() -> void:
	var paused: bool = bool(_card.get("paused", false))
	var fin: Dictionary = {}
	if GameState.is_story_campaign():
		var raw: Variant = Mission.story.get("final", {})
		if raw is Dictionary:
			fin = raw
	var ending: Dictionary = Mission.ending
	_kicker.text = "SOL %02d / %d  ·  FINAL TRANSMISSION" % [Mission.sol, GameState.target_sols]
	_title.text = (str(fin.get("title", "")) if not paused and not fin.is_empty() else str(ending.get("title", "MISSION REPORT"))).to_upper()
	_location.text = "LOCATION: %s" % str(fin.get("location", "Main Control Room"))
	var accomplished: bool = str(ending.get("id", "")) == "mission_accomplished"
	_set_alert("red" if paused else ("green" if accomplished else "yellow"))
	_scene_label.text = str(fin.get("scene", "")) if not paused else \
		"Life support can no longer keep up. NOVA freezes all non-essential systems and prepares the report."
	if not fin.is_empty():
		_lines = _filter_lines(fin.get("dialogue_paused" if paused else "dialogue", []))
	if _lines.is_empty():
		if paused:
			_lines = [{"speaker": "NOVA", "text": "Critical failure. Suspending the training scenario."}]
		else:
			_lines = [{"speaker": "NOVA", "text": "Training scenario complete. Sending the results to Earth Control."}]
		_lines.append({"speaker": "LAYLA", "text": str(ending.get("text", "Here is your evaluation, Commander."))})
	if paused:
		_lines.append({"speaker": "LOG", "text": "Mission paused on Sol %d: %s." % [Mission.sol, str(_card.get("reason", "critical failure"))]})
	elif not ending.is_empty():
		# The script's closing lines are the same for every completed run; the log
		# line states which ending the evaluation actually awarded.
		_lines.append({"speaker": "LOG", "text": "Outcome: %s. %s" % [
			str(ending.get("title", "")), str(ending.get("text", ""))]})
	_ctx_default()


func _setup_briefing() -> void:
	var sc: Dictionary = GameState.get_scenario()
	_kicker.text = "%s  ·  SOLS %d-%d" % [str(sc.get("menu_tag", "TRAINING")), int(sc.get("start_sol", 1)), int(sc.get("end_sol", 1))]
	_title.text = str(sc.get("title", "Training Scenario")).to_upper()
	_location.text = "LANDING SITE: %s" % GameState.get_landing_site_name()
	_set_alert("blue")
	_scene_label.text = str(sc.get("description", "A focused training run with its own objectives."))
	_lines = [
		{"speaker": "NOVA", "text": "Training scenario loaded: %s. It runs from Sol %d to Sol %d." % [
			str(sc.get("title", "")), int(sc.get("start_sol", 1)), int(sc.get("end_sol", 1))]},
		{"speaker": "LAYLA", "text": "Your objectives are on the right, Commander. Earth Control is standing by."},
	]
	_clear(_context)
	_ctx_heading("SCENARIO OBJECTIVES")
	for o: Dictionary in Mission.get_objective_lines():
		_ctx_text("○  %s" % str(o["text"]), 13, TEXT)
	var schedule: Variant = sc.get("scripted_event_schedule", {})
	if schedule is Dictionary and not (schedule as Dictionary).is_empty():
		_ctx_heading("SCHEDULED EVENTS")
		for key: String in schedule:
			_ctx_text("Sol %s: %s" % [key, str(DataLoader.get_event(str(schedule[key])).get("name", schedule[key]))], 13, TEXT)
	_ctx_text("Random events: %s" % ("ON" if bool(sc.get("random_events_enabled", false)) else "OFF"), 12, MUTED)


# ==================== typing ====================

func _escape(text: String) -> String:
	return text.replace("[", "[lb]")


func _advance() -> void:
	if _typing:
		_finish_line()
		return
	if _line_index + 1 < _lines.size():
		_line_index += 1
		_type_line(_lines[_line_index])
	elif not _choices_shown and not _result_shown:
		_show_choices()


func _skip_lines() -> void:
	if _choices_shown:
		return
	_typing = false
	while _line_index + 1 < _lines.size():
		_line_index += 1
		_append_line(_lines[_line_index])
	_dialogue.visible_characters = -1
	_show_choices()


func _append_line(line: Dictionary) -> void:
	var key: String = str(line.get("speaker", "LOG"))
	var sp: Dictionary = _speakers.get(key, DEFAULT_SPEAKERS["LOG"])
	var head: String = "[color=%s][b]%s[/b][/color]" % [str(sp.get("color", "#FFFFFF")), str(sp.get("name", key)).to_upper()]
	var role: String = str(sp.get("role", ""))
	if not role.is_empty():
		head += " [color=#8C8580]· %s[/color]" % role
	var body: String = _escape(Mission.format_text(str(line.get("text", ""))))
	if key == "LOG":
		body = "[i][color=#C9C2B8]%s[/color][/i]" % body
	else:
		body = "[color=#EDE7E0]%s[/color]" % body
	var prefix: String = "\n\n" if _dialogue.get_total_character_count() > 0 else ""
	_dialogue.append_text(prefix + head + "\n" + body)


func _type_line(line: Dictionary) -> void:
	_chars_from = _dialogue.get_total_character_count()
	_append_line(line)
	_chars_to = _dialogue.get_total_character_count()
	_typed = 0.0
	_typing = true
	_dialogue.visible_characters = _chars_from
	_update_footer()


func _finish_line() -> void:
	_typing = false
	_dialogue.visible_characters = -1
	if _line_index + 1 >= _lines.size():
		_show_choices()
	else:
		_update_footer()


func _update_footer() -> void:
	if _choices_shown:
		return
	_next_button.visible = true
	_footer.text = "Line %d of %d  ·  SPACE or click to continue" % [_line_index + 1, _lines.size()]


func _process(delta: float) -> void:
	if not _typing:
		return
	_typed += delta * CHARS_PER_SECOND
	var shown: int = _chars_from + int(_typed)
	if shown >= _chars_to:
		_finish_line()
	else:
		_dialogue.visible_characters = shown


func _on_dialogue_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not _choices_shown:
			_advance()


func _input(event: InputEvent) -> void:
	if not is_open() or not (event is InputEventKey):
		return
	get_viewport().set_input_as_handled()
	if not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			if not _choices_shown:
				_advance()
			elif _result_shown:
				_show_next()
		KEY_1, KEY_2, KEY_3, KEY_4:
			var index: int = int(event.keycode - KEY_1)
			if _choices_shown and not _result_shown and index < _pick_list.size():
				(_pick_list[index] as Callable).call()


# ==================== choices ====================

func _choice_list() -> Array:
	match str(_card.get("kind", "")):
		"story":
			return (_card.get("day", {}) as Dictionary).get("choices", [])
		"event":
			return ((_card.get("event", {}) as Dictionary).get("def", {}) as Dictionary).get("player_choices", [])
	return []


func _show_choices() -> void:
	if _choices_shown:
		return
	_choices_shown = true
	_typing = false
	_dialogue.visible_characters = -1
	_next_button.visible = false
	_skip_button.visible = false
	_clear(_choices)
	_pick_list.clear()
	var kind: String = str(_card.get("kind", ""))
	if kind == "final":
		var fin: Dictionary = Mission.story.get("final", {}) if Mission.story.get("final", {}) is Dictionary else {}
		var b := _button(str(fin.get("button", "OPEN FINAL EVALUATION")), Color(0.5, 1.0, 0.6))
		b.custom_minimum_size = Vector2(LEFT_W, 46)
		b.pressed.connect(_open_evaluation)
		_choices.add_child(b)
		_pick_list.append(_open_evaluation)
		_footer.text = "The Final Evaluation reviews every decision of the run."
		return
	if kind == "briefing":
		var start := _button("BEGIN SCENARIO", Color(0.5, 1.0, 0.6))
		start.custom_minimum_size = Vector2(LEFT_W, 46)
		start.pressed.connect(_continue)
		_choices.add_child(start)
		_pick_list.append(_continue)
		_footer.text = "The Sol clock starts when you close this briefing."
		return
	var list: Array = _choice_list()
	var any_ok: bool = false
	var index: int = 0
	for raw: Variant in list:
		if not raw is Dictionary:
			continue
		var ch: Dictionary = raw
		if not Mission.condition_ok(ch):
			continue
		index += 1
		var reason: String = Mission.choice_block_reason(_card, ch)
		var btn: Button = _choice_button(index, ch, reason)
		_choices.add_child(btn)
		var cb: Callable = _pick.bind(ch)
		if reason.is_empty():
			any_ok = true
			btn.pressed.connect(cb)
			_pick_list.append(cb)
		else:
			_pick_list.append(func() -> void: AudioManager.play_ui_error())
	if not any_ok:
		var fallback: Dictionary = {
			"id": "no_response", "label": "No affordable response — take the full impact",
			"detail": "Not one option can be paid for with the current stores.",
			"event_resolution": "unprotected" if not (_card.get("event", {}) as Dictionary).is_empty() else "",
			"scores": {"resources": -2}, "fallback": true,
			"consequence": "No option could be paid for. The base absorbs the full impact of the problem.",
		}
		var fb: Button = _choice_button(index + 1, fallback, "")
		var fcb: Callable = _pick.bind(fallback)
		fb.pressed.connect(fcb)
		_choices.add_child(fb)
		_pick_list.append(fcb)
	_footer.text = "Choose with the mouse or press 1-%d. Costs are paid at once." % _pick_list.size()


func _choice_cost_text(ch: Dictionary) -> String:
	var def: Dictionary = {}
	if not str(ch.get("event_id", "")).is_empty():
		def = DataLoader.get_event(str(ch["event_id"]))
	else:
		def = (_card.get("event", {}) as Dictionary).get("def", {})
	var cost: Dictionary = Mission.choice_cost(ch, def)
	if cost.is_empty():
		return "NO COST"
	var parts: PackedStringArray = PackedStringArray()
	for key: String in cost:
		parts.append("%d %s" % [int(cost[key]), ResourceManager.get_display_name(key)])
	return "COST: " + ", ".join(parts)


func _choice_button(index: int, ch: Dictionary, reason: String) -> Button:
	var ok: bool = reason.is_empty()
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(LEFT_W, 60)
	btn.disabled = not ok
	btn.add_theme_stylebox_override("normal", _box(Color(0.1, 0.075, 0.08), Color(1.0, 0.55, 0.25, 0.55), 1, 4, 8))
	btn.add_theme_stylebox_override("hover", _box(Color(0.2, 0.11, 0.07), ACCENT, 2, 4, 8))
	btn.add_theme_stylebox_override("pressed", _box(Color(0.3, 0.15, 0.07), ACCENT, 2, 4, 8))
	btn.add_theme_stylebox_override("disabled", _box(Color(0.06, 0.06, 0.07), Color(0.3, 0.3, 0.33), 1, 4, 8))
	if ok:
		btn.mouse_entered.connect(AudioManager.play_ui_hover)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 4)
	btn.add_child(margin)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 1)
	margin.add_child(col)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	var title := _label(15, Color(1.0, 0.86, 0.62) if ok else Color(0.5, 0.5, 0.52))
	title.text = "%d   %s" % [index, Mission.format_text(str(ch.get("label", "")))]
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var cost := _label(12, Color(0.6, 0.9, 1.0) if ok else Color(1.0, 0.45, 0.4))
	cost.text = _choice_cost_text(ch) if ok else "LOCKED: %s" % reason
	if bool(ch.get("fallback", false)):
		cost.text = "ALWAYS AVAILABLE"
	top.add_child(cost)
	var detail: String = str(ch.get("detail", ""))
	if detail.is_empty():
		detail = _effects_text(ch.get("effects", []), true)
	var d := _label(12, Color(0.78, 0.74, 0.7) if ok else Color(0.45, 0.45, 0.47), true)
	d.text = Mission.format_text(detail)
	col.add_child(d)
	return btn


func _pick(ch: Dictionary) -> void:
	if _result_shown or not _choices_shown:
		return
	AudioManager.play_ui_confirm()
	var result: Dictionary = {}
	match str(_card.get("kind", "")):
		"story":
			result = Mission.choose_story(_card, ch)
		"event":
			result = Mission.choose_event(_card, "" if bool(ch.get("fallback", false)) else str(ch.get("id", "")))
	_show_result(ch, result)


func _show_result(ch: Dictionary, result: Dictionary) -> void:
	_result_shown = true
	_clear(_choices)
	_pick_list.clear()
	var decision := _label(13, ACCENT)
	decision.text = "YOUR DECISION: %s" % Mission.format_text(str(ch.get("label", ""))).to_upper()
	_choices.add_child(decision)
	var consequence := _label(15, TEXT, true)
	consequence.text = str(result.get("consequence", ""))
	_choices.add_child(consequence)
	var changes := _label(13, Color(0.6, 0.95, 0.75), true)
	var diff: String = str(result.get("changes", ""))
	changes.text = "Changes: %s" % diff if not diff.is_empty() else "No immediate change to the stores."
	_choices.add_child(changes)
	var insight: String = str(result.get("insight", ""))
	if not insight.is_empty():
		var box := PanelContainer.new()
		box.add_theme_stylebox_override("panel", _box(Color(0.04, 0.07, 0.1, 0.95), Color(0.45, 0.75, 1.0, 0.7), 1, 4, 8))
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		box.add_child(col)
		var source: String = str(result.get("source", ""))
		var head := _label(12, Color(0.55, 0.85, 1.0))
		if str(_card.get("kind", "")) == "event":
			head.text = "MISSION LESSON"
		elif source.begins_with("Game lesson"):
			head.text = "MISSION LESSON"
		else:
			head.text = "NASA INSIGHT"
		col.add_child(head)
		var body := _label(13, Color(0.88, 0.92, 0.96), true)
		body.text = insight
		col.add_child(body)
		if not source.is_empty():
			var src := _label(11, Color(0.55, 0.62, 0.7), true)
			src.text = ("Further reading: " if str(_card.get("kind", "")) == "event" else "Source: ") + source
			col.add_child(src)
		_choices.add_child(box)
	var cont := _button("CONTINUE  >", Color(0.5, 1.0, 0.6))
	cont.custom_minimum_size = Vector2(LEFT_W, 40)
	cont.pressed.connect(_continue)
	_choices.add_child(cont)
	_footer.text = "SPACE or CONTINUE returns to the base." if not Mission.ended else "SPACE or CONTINUE opens the final transmission."
	_refresh_status()
	if str(_card.get("kind", "")) == "story" and not _history_open:
		var day: Dictionary = _card.get("day", {})
		if str(day.get("summary", "")).is_empty():
			var inst: Dictionary = _card.get("event", {})
			if inst.is_empty():
				_ctx_default()


func _continue() -> void:
	AudioManager.play_ui_confirm()
	_show_next()


func _open_evaluation() -> void:
	AudioManager.play_mission_confirm()
	var completed: bool = bool(Mission.ending.get("completed", false))
	_close(false)
	EventBus.mission_over.emit("complete" if completed else "failed", str(Mission.ending.get("reason", "")))


# ==================== right column ====================

func _refresh_status() -> void:
	for key: String in _status_rows:
		var row: Dictionary = _status_rows[key]
		var amount: int = ResourceManager.get_amount(key)
		var cap: int = ResourceManager.get_capacity(key)
		if key == "science":
			cap = maxi(1, Mission.get_science_target())
		var frac: float = clampf(float(amount) / float(maxi(cap, 1)), 0.0, 1.0)
		(row["fill"] as ColorRect).size = Vector2(190.0 * frac, 10)
		var ratio: float = ResourceManager.get_ratio(key)
		var color: Color = row["color"]
		var text_color: Color = TEXT
		if key != "science" and ratio < 0.3:
			color = Color(1.0, 0.35, 0.3)
			text_color = color
		elif key != "science" and ratio < 0.6:
			text_color = Color(1.0, 0.75, 0.35)
		(row["fill"] as ColorRect).color = color
		var value: Label = row["value"]
		value.text = "%d / %d" % [amount, cap]
		value.add_theme_color_override("font_color", text_color)


func _clear(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _ctx_heading(text: String, color: Color = ACCENT) -> void:
	var l := _label(13, color, true)
	l.text = text
	_context.add_child(l)


func _ctx_text(text: String, size: int = 12, color: Color = TEXT) -> Label:
	var l := _label(size, color, true)
	l.text = text
	_context.add_child(l)
	return l


func _ctx_bar(label: String, value: float, top: float, color: Color, suffix: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var l := _label(12, TEXT)
	l.text = label
	l.custom_minimum_size = Vector2(88, 0)
	row.add_child(l)
	var track := ColorRect.new()
	track.color = Color(0.15, 0.12, 0.13)
	track.custom_minimum_size = Vector2(150, 12)
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := ColorRect.new()
	fill.color = color
	fill.size = Vector2(150.0 * clampf(value / maxf(top, 0.001), 0.0, 1.0), 12)
	track.add_child(fill)
	row.add_child(track)
	var v := _label(12, color)
	v.text = suffix
	row.add_child(v)
	_context.add_child(row)


func _ctx_default() -> void:
	_clear(_context)
	var week: Dictionary = Mission.get_week()
	if not week.is_empty():
		_ctx_heading("WEEK %d  ·  %s" % [int(week.get("week", 0)), str(week.get("title", "")).to_upper()])
	var phase: Dictionary = Mission.get_phase()
	if not phase.is_empty():
		_ctx_text("Phase focus: %s" % str(phase.get("focus", "")), 12, MUTED)
	_ctx_heading("ACTIVE EFFECTS")
	var active: Array = Mission.get_active_labels()
	if active.is_empty():
		_ctx_text("Nothing unusual is affecting the base.", 12, MUTED)
	for label: Variant in active:
		_ctx_text("•  %s" % str(label), 12, Color(1.0, 0.7, 0.5))
	_ctx_heading("SYSTEMS")
	for sys_id: Variant in Mission.get_system_ids():
		var id: String = str(sys_id)
		var sys_name: String = str(Mission.get_system_def(id).get("name", id))
		var state: String = "ONLINE" if Mission.is_system_enabled(id) else "OFF"
		var color: Color = Color(0.55, 1.0, 0.6) if state == "ONLINE" else MUTED
		if Mission.is_system_locked(id):
			state = "LOCKED"
			color = Color(1.0, 0.45, 0.4)
		_ctx_text("%s  —  %s" % [sys_name, state], 12, color)


func _ctx_event(inst: Dictionary) -> void:
	_clear(_context)
	var def: Dictionary = inst.get("def", {})
	_ctx_heading("EVENT FILE: %s" % str(def.get("name", "")).to_upper(), Color(1.0, 0.55, 0.45))
	_ctx_text("Gameplay event from data/events.json (game balance values).", 11, MUTED)
	var impact: String = _effects_text(def.get("effects", []), false)
	if not impact.is_empty():
		_ctx_text("Immediate impact: %s" % impact, 12, TEXT)
	if Mission.is_radiation_event(def):
		var req: Dictionary = Mission.radiation_requirements(inst)
		_ctx_heading("SHIELD REQUIREMENTS")
		var shield_on: bool = Mission.is_system_enabled(str(req["system"]))
		_ctx_text("%s  Shield generator online" % ("✔" if shield_on else "✖"), 12,
			Color(0.55, 1.0, 0.6) if shield_on else Color(1.0, 0.45, 0.4))
		_ctx_bar("Energy", ResourceManager.get_amount("energy"), float(req["energy"]), Color(1.0, 0.82, 0.3),
			"%d / %d" % [ResourceManager.get_amount("energy"), int(req["energy"])])
		_ctx_bar("Shield", ResourceManager.get_amount("shield"), float(req["shield"]), Color(0.75, 0.55, 1.0),
			"%d / %d" % [ResourceManager.get_amount("shield"), int(req["shield"])])
		_ctx_text("Unprotected crew: -%d crew health." % Mission.radiation_penalty(inst), 12, Color(1.0, 0.6, 0.5))
	var source: Dictionary = def.get("source", {})
	if not source.is_empty():
		_ctx_text("Reference: %s · %s" % [str(source.get("organization", "")), str(source.get("title", ""))], 11, MUTED)


func _ctx_week() -> void:
	_clear(_context)
	var week: Dictionary = Mission.get_week()
	_ctx_heading("WEEK %d REPORT" % int(week.get("week", 1)))
	var survived: int = 0
	for key: String in Mission.events_survived:
		survived += int(Mission.events_survived[key])
	_ctx_text("Sols completed: %d" % Mission.completed_sols)
	_ctx_text("Decisions logged: %d" % Mission.decisions.size())
	_ctx_text("Emergencies handled: %d" % survived)
	_ctx_text("Sols with a supply under 30%%: %d" % Mission.shortage_sols,
		12, Color(1.0, 0.6, 0.5) if Mission.shortage_sols > 0 else TEXT)
	_ctx_text("Achievements: %d" % Mission.achievements_unlocked.size())
	_ctx_heading("SUPPLY: START  >  NOW")
	for id: String in Mission.SUPPLY:
		var start: int = ResourceManager.get_start_amount(id)
		var now: int = ResourceManager.get_amount(id)
		_ctx_bar(ResourceManager.get_display_name(id), now, maxf(float(start), float(now)),
			Color(0.55, 1.0, 0.6) if now >= start else Color(1.0, 0.7, 0.4), "%d > %d (%+d)" % [start, now, now - start])


func _ctx_history() -> void:
	_clear(_context)
	_ctx_heading("RESOURCE HISTORY  ·  SOL 1-%d" % Mission.completed_sols)
	var graph := HistoryGraph.new()
	graph.custom_minimum_size = Vector2(RIGHT_W - 20, 150)
	graph.rows = Mission.history.duplicate()
	_context.add_child(graph)
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 12)
	for s: Variant in graph.series:
		var l := _label(12, s[1])
		l.text = "■ %s" % ResourceManager.get_display_name(str(s[0]))
		legend.add_child(l)
	_context.add_child(legend)
	if not Mission.history.is_empty():
		var first: Dictionary = Mission.history[0]
		var last: Dictionary = Mission.history[Mission.history.size() - 1]
		for id: String in Mission.SUPPLY:
			_ctx_text("%s: %d at end of Sol %d  >  %d at end of Sol %d" % [ResourceManager.get_display_name(id),
				int(first.get(id, 0)), int(first.get("sol", 1)), int(last.get(id, 0)), int(last.get("sol", 1))], 12, MUTED)


func _ctx_science() -> void:
	_clear(_context)
	var target: int = Mission.get_science_target()
	var science: int = ResourceManager.get_amount("science")
	_ctx_heading("SCIENCE PROGRESS")
	_ctx_bar("Science", science, target, Color(0.85, 0.65, 1.0), "%d / %d" % [science, target])
	var lab: String = "ONLINE" if Mission.is_system_enabled("research_lab") else "OFF"
	if Mission.is_system_locked("research_lab"):
		lab = "LOCKED (%s)" % Mission.get_lock_reason("research_lab")
	_ctx_text("Research lab: %s" % lab)
	var per_sol: int = int(Mission.get_system_def("research_lab").get("produces", {}).get("science_points", 2))
	var left: int = maxi(0, GameState.target_sols - Mission.sol + 1)
	_ctx_text("Sols left including today: %d" % left)
	var projected: int = science + per_sol * left
	_ctx_text("If the lab runs every remaining Sol: about %d science." % projected, 12,
		Color(0.55, 1.0, 0.6) if projected >= target else Color(1.0, 0.7, 0.4))
	if ResourceManager.get_amount("crew_morale") < 40:
		_ctx_text("Morale is under 40: the lab works at half speed.", 12, Color(1.0, 0.6, 0.5))


func _ctx_faults() -> void:
	_clear(_context)
	_ctx_heading("FAULT LOG")
	var faults: Array = Mission.faults
	if faults.is_empty():
		_ctx_text("No system ran short of power or water so far.", 12, Color(0.55, 1.0, 0.6))
	for i: int in range(maxi(0, faults.size() - 8), faults.size()):
		_ctx_text("•  %s" % str(faults[i]), 12, Color(1.0, 0.7, 0.5))
	_ctx_text("Base integrity: %d / %d" % [ResourceManager.get_amount("base_integrity"),
		ResourceManager.get_capacity("base_integrity")])
	var active: Array = Mission.get_active_labels()
	if not active.is_empty():
		_ctx_heading("STILL ACTIVE")
		for label: Variant in active:
			_ctx_text("•  %s" % str(label), 12, Color(1.0, 0.7, 0.5))


## The archived DONKI record + Curiosity RAD readings (Day 4 / historical scenario).
func _toggle_history() -> void:
	AudioManager.play_ui_confirm()
	if _history_open:
		_history_open = false
		_history_button.text = "VIEW HISTORICAL DATA"
		var inst: Dictionary = _card.get("event", {})
		if not inst.is_empty():
			_ctx_event(inst)
		else:
			_ctx_default()
		return
	_history_open = true
	_history_button.text = "HIDE HISTORICAL DATA"
	Mission.set_flag("player_opened_historical_data")
	var ref: String = ""
	if str(_card.get("kind", "")) == "story":
		ref = str((_card.get("day", {}) as Dictionary).get("historical_ref", ""))
	if ref.is_empty():
		ref = str((_card.get("event", {}) as Dictionary).get("historical_ref", ""))
	_clear(_context)
	var raw: Variant = DataLoader.load_json("res://data/nasa/solar_events.json", {})
	var file: Dictionary = raw if raw is Dictionary else {}
	var banner := PanelContainer.new()
	banner.add_theme_stylebox_override("panel", _box(Color(0.35, 0.1, 0.06, 0.95), Color(1.0, 0.5, 0.3), 1, 4, 6))
	var warn := _label(12, Color(1.0, 0.85, 0.7), true)
	warn.text = "HISTORICAL RECORD (2017), NOT A LIVE ALERT. %s" % str(file.get("warning", ""))
	banner.add_child(warn)
	_context.add_child(banner)
	var rec: Dictionary = DataLoader.get_solar_event(ref)
	if rec.is_empty():
		_ctx_text("No archived record linked to this card.", 12, MUTED)
		return
	_ctx_heading("NASA DONKI  ·  %s" % str(rec.get("name", "")).to_upper(), Color(0.55, 0.85, 1.0))
	_ctx_text("Type: %s  ·  Observed near Earth: %s" % [str(rec.get("donki_type", "")), str(rec.get("donki_observed_near_earth", "")).replace("T", " ").replace("Z", " UTC")])
	_ctx_text("Mars surface event window: %s to %s" % [str(rec.get("date_start", "")), str(rec.get("date_end", ""))])
	_ctx_text(str(rec.get("reported_context", "")), 12, MUTED)
	var meas: Dictionary = DataLoader.get_radiation_measurement(str(rec.get("linked_measurement_id", "")))
	if not meas.is_empty():
		var unit: String = str(meas.get("unit", ""))
		_ctx_heading("CURIOSITY RAD  ·  %s" % str(meas.get("quantity", "")).to_upper(), Color(0.55, 0.85, 1.0))
		_ctx_text("%s, %s" % [str(meas.get("dataset", "")), str(meas.get("location_context", ""))], 11, MUTED)
		var top: float = 1.0
		for v: Variant in meas.get("values", []):
			top = maxf(top, float((v as Dictionary).get("value", 0.0)))
		for v: Variant in meas.get("values", []):
			var row: Dictionary = v
			var value: float = float(row.get("value", 0.0))
			_ctx_bar(str(row.get("date", "")), value, top * 1.05,
				Color(1.0, 0.45, 0.35) if value >= top else Color(0.55, 0.85, 1.0), "%.2f %s" % [value, unit])
			_ctx_text("    %s (%d readings)" % [str(row.get("role", "")), int(row.get("sample_count", 0))], 11, MUTED)
		_ctx_text(str(meas.get("interpretation", "")), 12, TEXT)
	var thr: Dictionary = DataLoader.get_threshold_for(ref)
	if not thr.is_empty():
		_ctx_heading("GAME TRANSLATION (balance values)")
		_ctx_text("Shield needed: %d  ·  Unprotected crew health: -%d" % [int(thr.get("shield_required", 0)),
			int(thr.get("crew_health_penalty_if_unprotected", 0))])
		_ctx_text(str(thr.get("note", "")), 11, MUTED)
	var src: Dictionary = rec.get("source", {})
	_ctx_text("Sources: %s  ·  %s" % [str(src.get("url", "")), str(src.get("related_source_url", ""))], 11, Color(0.55, 0.62, 0.7))


# ==================== text helpers ====================

## "Base Integrity -12, Science +3" from an effects list (gameplay values).
func _effects_text(effects: Variant, include_zero: bool) -> String:
	var parts: PackedStringArray = PackedStringArray()
	if not effects is Array:
		return ""
	for raw: Variant in effects:
		if not raw is Dictionary:
			continue
		var e: Dictionary = raw
		var target: String = str(e.get("target", ""))
		var op: String = str(e.get("operation", ""))
		var prop: String = str(e.get("property", ""))
		if op == "add" or op == "subtract":
			var v: int = int(e.get("value", 0))
			if v == 0 and not include_zero:
				continue
			if v == 0:
				continue
			parts.append("%s %s%d" % [ResourceManager.get_display_name(target), "+" if op == "add" else "-", v])
		elif op == "add_per_sol" or op == "subtract_per_sol":
			parts.append("%s %s%d per Sol" % [ResourceManager.get_display_name(target), "+" if op == "add_per_sol" else "-", int(e.get("value", 0))])
		elif prop == "enabled":
			var sys_name: String = str(Mission.get_system_def(target).get("name", target.replace("_", " ")))
			parts.append("%s %s" % [sys_name, "online" if bool(e.get("value", false)) else "offline"])
		elif prop.ends_with("_multiplier"):
			var mod_name: String = str(Mission.get_system_def(target).get("name", target.replace("_", " ").capitalize()))
			parts.append("%s %s x%.2f" % [mod_name, prop.replace("_multiplier", "").replace("_", " "), float(e.get("value", 1.0))])
		elif prop == "dust":
			parts.append("Solar panels %s" % ("dusty" if bool(e.get("value", false)) else "cleaned"))
	return ", ".join(parts)
