## scripts/menu_main.gd
## The boot flow the pack was drawn for:  MAIN MENU -> MISSION BRIEFING -> LOADING -> game.
## Day 0 sits between the briefing and the loading screen: START opens the landing-site
## map (scripts/landing_select.gd) and only a confirmed site launches the mission.
##
## The three screens (assets/ui/screens/main_menu.png, start_mission.png, loading.png) are
## painted at 1376x768 including their buttons, so this script only cuts the painted
## buttons out of the artwork and makes them real controls.  SETTINGS and CREDITS have no
## artwork of their own, so they use plain panels styled to match the HUD palette.
extends Node

const MENU_ART := "res://assets/ui/screens/main_menu.png"
const BRIEF_ART := "res://assets/ui/screens/start_mission.png"
const LOADING_ART := "res://assets/ui/screens/loading.png"
const LandingScreen := preload("res://scripts/landing_select.gd")

## Button regions in main_menu.png pixels.
const BTN_PLAY := Rect2(88, 348, 254, 90)
const BTN_SETTINGS := Rect2(88, 442, 254, 80)
const BTN_CREDITS := Rect2(88, 524, 254, 80)
const BTN_EXIT := Rect2(88, 617, 254, 84)

## Button regions in start_mission.png pixels.
const BTN_BACK := Rect2(290, 648, 160, 74)
const BTN_START := Rect2(455, 596, 472, 130)

const PANEL_BG := Color(0.05, 0.07, 0.12, 0.95)
const PANEL_BORDER := Color(0.35, 0.75, 0.9, 0.9)
const TEXT := Color(0.94, 0.97, 1.0)
const ACCENT := Color(1.0, 0.72, 0.35)

var _root: Control
var _art: TextureRect
var _controls: Array[Control] = []
var _modal: Control
var _mode: StringName = &"menu"
var _mission_buttons: Dictionary = {}
var _difficulty_buttons: Dictionary = {}
var _sol_badge: Label
var _exit_note: Label
var _brief_line: Label
var _objective_box: Label


func _ready() -> void:
	AudioManager.enter_menu()
	var layer := CanvasLayer.new()
	layer.name = "MenuCanvas"
	layer.layer = 20
	add_child(layer)

	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_root)

	_art = UiRegions.add_fullscreen_art(_root, null, "MenuArt")
	show_menu()


func _clear_controls() -> void:
	for control: Control in _controls:
		control.queue_free()
	_controls.clear()
	if _modal != null and is_instance_valid(_modal):
		_modal.queue_free()
	_modal = null


# ==================== screens ====================

func show_menu() -> void:
	_mode = &"menu"
	_clear_controls()
	var art := load(MENU_ART) as Texture2D
	_art.texture = art
	_button(art, BTN_PLAY, "Play", show_briefing)
	_button(art, BTN_SETTINGS, "Settings", show_settings)
	_button(art, BTN_CREDITS, "Credits", show_credits)
	_button(art, BTN_EXIT, "Exit", _quit)
	var version := _text(Rect2(880, 700, 460, 40),
		"AstroBase-Commander · NovaCore · NASA Space Apps", 26, Color(0.85, 0.9, 0.95, 0.8))
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func show_briefing() -> void:
	_mode = &"briefing"
	_clear_controls()
	var art := load(BRIEF_ART) as Texture2D
	_art.texture = art
	_button(art, BTN_BACK, "Back", show_menu)
	_button(art, BTN_START, "Start", show_landing)
	_build_mission_picker()
	_build_difficulty_picker()
	# The painted "30 SOLS" badge follows the chosen scenario.
	_sol_badge = UiRegions.add_label(_root, Rect2(858, 42, 134, 40), 22, ACCENT)
	_controls.append(_sol_badge)
	_controls.append(_sol_badge.get_parent().get_child(_sol_badge.get_index() - 1) as Control)
	# Keep the briefing honest about the speed picked in SETTINGS and the chosen run.
	_brief_line = _text(Rect2(253, 684, 781, 30), "", 17, Color(0.8, 0.9, 1.0, 0.95))
	_refresh_briefing()


## Five pack scenarios (data/scenarios/scenarios.json): the story campaign first, then
## the four short training runs, each labelled with its menu_tag.
func _build_mission_picker() -> void:
	var column := _side_panel(Rect2(10, 30, 236, 556), "SELECT MISSION")
	_mission_buttons.clear()
	var rows: Array = []
	for row: Variant in DataLoader.get_scenarios():
		if row is Dictionary:
			if str((row as Dictionary).get("id", "")) == GameState.CAMPAIGN_ID:
				rows.push_front(row)
			else:
				rows.append(row)
	for row: Dictionary in rows:
		var id: String = str(row.get("id", ""))
		var button := _choice_button("%s\n%s\nSOL %d–%d" % [
			str(row.get("menu_tag", "")).to_upper(), str(row.get("title", id)),
			int(row.get("start_sol", 1)), int(row.get("end_sol", 30))], 15)
		button.custom_minimum_size = Vector2(212, 92)
		button.pressed.connect(func() -> void:
			GameState.set_scenario(id)
			_refresh_briefing()
		)
		column.add_child(button)
		_mission_buttons[id] = button


func _build_difficulty_picker() -> void:
	var column := _side_panel(Rect2(1040, 30, 232, 556), "DIFFICULTY")
	_difficulty_buttons.clear()
	var levels: Dictionary = GameState.get_difficulty_levels()
	for level: String in ["easy", "normal", "hard"]:
		if not levels.has(level):
			continue
		var spec: Dictionary = levels[level] as Dictionary
		var button := _choice_button("%s\nuse ×%.2f · events ×%.2f" % [level.to_upper(),
			float(spec.get("resource_multiplier", 1.0)), float(spec.get("event_chance_multiplier", 1.0))], 15)
		button.custom_minimum_size = Vector2(208, 64)
		button.pressed.connect(func() -> void:
			GameState.set_difficulty(level)
			_refresh_briefing()
		)
		column.add_child(button)
		_difficulty_buttons[level] = button
	var note := Label.new()
	note.text = "Game balance values from game_config.json: daily use / event damage and the 35% end-of-Sol event roll."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(208, 0)
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color(0.6, 0.78, 0.88))
	column.add_child(note)
	_objective_box = Label.new()
	_objective_box.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective_box.custom_minimum_size = Vector2(208, 0)
	_objective_box.add_theme_font_size_override("font_size", 14)
	_objective_box.add_theme_color_override("font_color", TEXT)
	column.add_child(_objective_box)


func _refresh_briefing() -> void:
	for id: String in _mission_buttons:
		_paint_choice(_mission_buttons[id] as Button, id == GameState.scenario_id)
	for level: String in _difficulty_buttons:
		_paint_choice(_difficulty_buttons[level] as Button, level == GameState.difficulty)
	var scenario: Dictionary = GameState.get_scenario()
	var first: int = int(scenario.get("start_sol", 1))
	var last: int = int(scenario.get("end_sol", 30))
	if _sol_badge != null:
		_sol_badge.text = "%d SOLS" % (last - first + 1)
	if _objective_box != null:
		var lines := PackedStringArray(["OBJECTIVES"])
		for obj: Variant in scenario.get("objectives", []):
			if obj is Dictionary:
				lines.append("• " + str((obj as Dictionary).get("description", "")))
		var reward: Variant = scenario.get("completion_reward", {})
		if reward is Dictionary and (reward as Dictionary).has("science_points"):
			lines.append("Reward: +%d science" % int((reward as Dictionary)["science_points"]))
		_objective_box.text = "\n".join(lines)
	if _brief_line != null:
		var minutes: int = int(GameState.sol_seconds) / 60
		var seconds: int = int(GameState.sol_seconds) % 60
		_brief_line.text = "%s · Sols %d–%d · %s · one Sol = %d:%02d min · TAB = NASA data" % [
			str(scenario.get("title", "Mission")), first, last, GameState.difficulty.to_upper(),
			minutes, seconds]


func _side_panel(rect: Rect2, title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.06, 0.1, 0.9)
	style.border_color = PANEL_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	panel.position = rect.position
	panel.size = rect.size
	_root.add_child(panel)
	_controls.append(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var heading := Label.new()
	heading.text = title
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 20)
	heading.add_theme_color_override("font_color", ACCENT)
	column.add_child(heading)
	return column


func _choice_button(content: String, font_size: int) -> Button:
	var button := _flat_button(content)
	button.add_theme_font_size_override("font_size", font_size)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return button


func _paint_choice(button: Button, selected: bool) -> void:
	if button == null:
		return
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.1, 0.32, 0.4, 0.95) if selected else Color(0.08, 0.1, 0.15, 0.95)
		if state == "hover":
			box.bg_color = box.bg_color.lightened(0.12)
		box.border_color = ACCENT if selected else Color(0.3, 0.45, 0.55, 0.8)
		box.set_border_width_all(3 if selected else 1)
		box.set_corner_radius_all(6)
		box.set_content_margin_all(8)
		button.add_theme_stylebox_override(state, box)
	button.add_theme_color_override("font_color", Color(1, 1, 1) if selected else Color(0.82, 0.88, 0.94))


func show_loading() -> void:
	_mode = &"loading"
	_clear_controls()
	_art.texture = load(LOADING_ART) as Texture2D


## DAY 0 — the Main Control Room landing map.
func show_landing() -> void:
	_mode = &"landing"
	_clear_controls()
	_art.texture = null
	var screen := LandingScreen.new()
	screen.name = "LandingSelect"
	_root.add_child(screen)
	_controls.append(screen)
	screen.site_confirmed.connect(func(_site_id: String) -> void: _launch_mission())
	screen.back_requested.connect(show_briefing)


func _launch_mission() -> void:
	show_loading()
	GameState.begin_mission()
	# Paint the loading screen first, then block on the actual scene load: the game
	# only starts once the artwork is on screen (a real load takes ~a second here).
	await get_tree().process_frame
	await get_tree().process_frame
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		push_error("menu_main: res://scenes/main.tscn failed to load")
		show_menu()
		return
	get_tree().change_scene_to_packed(packed)


func _quit() -> void:
	# A web page cannot close its own tab: tell the player instead of a dead button.
	if OS.has_feature("web"):
		if _exit_note == null or not is_instance_valid(_exit_note):
			_exit_note = _text(Rect2(880, 655, 460, 40), "Close the browser tab to leave the mission.", 24, ACCENT)
			_exit_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		return
	GameState.mission_running = false
	get_tree().quit()


# ==================== settings / credits (no artwork shipped for these) ====================

func show_settings() -> void:
	_modal = _panel("MISSION SETTINGS", Vector2(560, 320))
	var column := _column(_modal)

	column.add_child(_label_row("SOL LENGTH (real time per Martian day)"))
	var speeds := HBoxContainer.new()
	speeds.add_theme_constant_override("separation", 12)
	column.add_child(speeds)
	for spec: Array in [["QUICK", 90.0], ["STANDARD", 180.0], ["RELAXED", 240.0]]:
		var pick := _flat_button("%s %d:%02d" % [spec[0], int(spec[1]) / 60, int(spec[1]) % 60])
		pick.pressed.connect(func() -> void:
			GameState.sol_seconds = float(spec[1])
			_flash("%s  ·  one Sol = %d:%02d min" % [spec[0], int(spec[1]) / 60, int(spec[1]) % 60])
		)
		speeds.add_child(pick)
	_flash("Current: one Sol = %d:%02d min (QUICK is the demo default)" % [
		int(GameState.sol_seconds) / 60, int(GameState.sol_seconds) % 60])

	column.add_child(_label_row("WINDOW"))
	var window := _flat_button("TOGGLE FULLSCREEN")
	window.pressed.connect(_toggle_fullscreen)
	column.add_child(window)

	var back := _flat_button("BACK")
	back.pressed.connect(show_menu)
	column.add_child(back)


func show_credits() -> void:
	_modal = _panel("ASTROBASE-COMMANDER", Vector2(660, 430))
	var column := _column(_modal)
	var lines := PackedStringArray()
	lines.append("NovaCore team — NASA Space Apps Challenge")
	lines.append("2D top-down colony survival for junior astronauts (7-12)")
	lines.append("")
	lines.append("Real data shipped offline: NASA CCMC DONKI, NASA OSDR RadLab")
	lines.append("(Curiosity MSL-RAD-Surface), NASA Mars Exploration, CSA.")
	lines.append("NASA numbers live in data/nasa/*.json; everything else is game balance.")
	lines.append("")
	lines.append("Artwork & interface: Stitch asset pack v2")
	lines.append("Engine: Godot 4 · pixel art · web export")
	var text := RichTextLabel.new()
	text.bbcode_enabled = false
	text.fit_content = false
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", 20)
	text.add_theme_color_override("default_color", TEXT)
	text.text = "\n".join(lines)
	column.add_child(text)

	var back := _flat_button("BACK")
	back.pressed.connect(show_menu)
	column.add_child(back)


func _flash(message: String) -> void:
	if _modal == null:
		return
	var column := _column(_modal)
	for child: Node in column.get_children():
		if child.name == "Flash":
			(child as Label).text = message
			return
	var label := Label.new()
	label.name = "Flash"
	label.text = message
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", ACCENT)
	column.add_child(label)


func _toggle_fullscreen() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


# ==================== small UI builders ====================

func _button(art: Texture2D, region: Rect2, name_hint: String, callback: Callable) -> void:
	var button := UiRegions.add_region_button(_root, art, region, name_hint)
	if button == null:
		return
	button.pressed.connect(callback)
	_controls.append(button)


func _text(rect: Rect2, content: String, font_size: int, color: Color) -> Label:
	var label := UiRegions.add_label(_root, rect, font_size, color)
	label.text = content
	_controls.append(label)
	return label


func _panel(title: String, size_v: Vector2) -> Control:
	var dim := ColorRect.new()
	dim.name = "ModalDim"
	dim.color = Color(0.01, 0.02, 0.05, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "ModalPanel"
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = PANEL_BORDER
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", style)
	panel.size = size_v
	panel.position = (Vector2(1280, 720) - size_v) * 0.5
	dim.add_child(panel)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)

	var heading := Label.new()
	heading.text = title.to_upper()
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 30)
	heading.add_theme_color_override("font_color", ACCENT)
	column.add_child(heading)
	return dim


func _column(dim: Control) -> VBoxContainer:
	return dim.get_node("ModalPanel/Column") as VBoxContainer


func _label_row(content: String) -> Label:
	var label := Label.new()
	label.text = content
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.9))
	return label


func _flat_button(content: String) -> Button:
	var button := Button.new()
	button.text = content
	button.custom_minimum_size = Vector2(180, 46)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 22)
	button.mouse_entered.connect(AudioManager.play_ui_hover)
	if content.to_lower().contains("back") or content.to_lower().contains("close"):
		button.pressed.connect(AudioManager.play_ui_back)
	else:
		button.pressed.connect(AudioManager.play_ui_confirm)
	return button
