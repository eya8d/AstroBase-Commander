## scripts/menu_main.gd
## The boot flow the pack was drawn for:  MAIN MENU -> MISSION BRIEFING -> LOADING -> game.
##
## The three screens (assets/ui/screens/main_menu.png, start_mission.png, loading.png) are
## painted at 1376x768 including their buttons, so this script only cuts the painted
## buttons out of the artwork and makes them real controls.  SETTINGS and CREDITS have no
## artwork of their own, so they use plain panels styled to match the HUD palette.
extends Node

const MENU_ART := "res://assets/ui/screens/main_menu.png"
const BRIEF_ART := "res://assets/ui/screens/start_mission.png"
const LOADING_ART := "res://assets/ui/screens/loading.png"

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
	_button(art, BTN_START, "Start", _launch_mission)
	# Keep the briefing honest about the speed the player picked in SETTINGS.
	_text(Rect2(250, 730, 620, 34),
		("Sol length: %.0f s · Objective: %d Sols"
			% [GameState.sol_seconds, GameState.target_sols]), 24, Color(0.8, 0.9, 1.0, 0.9))


func show_loading() -> void:
	_mode = &"loading"
	_clear_controls()
	_art.texture = load(LOADING_ART) as Texture2D


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
	GameState.mission_running = false
	get_tree().quit()


# ==================== settings / credits (no artwork shipped for these) ====================

func show_settings() -> void:
	_modal = _panel("MISSION SETTINGS", Vector2(560, 320))
	var column := _column(_modal)

	column.add_child(_label_row("SOL LENGTH (real seconds per Martian day)"))
	var speeds := HBoxContainer.new()
	speeds.add_theme_constant_override("separation", 12)
	column.add_child(speeds)
	for spec: Array in [["FAST", 6.0], ["NORMAL", 10.0], ["RELAXED", 15.0]]:
		var pick := _flat_button(String(spec[0]))
		pick.pressed.connect(func() -> void:
			GameState.sol_seconds = float(spec[1])
			_flash("%s  ·  one Sol = %.0f s" % [spec[0], float(spec[1])])
		)
		speeds.add_child(pick)

	column.add_child(_label_row("WINDOW"))
	var window := _flat_button("TOGGLE FULLSCREEN")
	window.pressed.connect(_toggle_fullscreen)
	column.add_child(window)

	var back := _flat_button("BACK")
	back.pressed.connect(show_menu)
	column.add_child(back)


func show_credits() -> void:
	_modal = _panel("MARS SURVIVAL ACADEMY", Vector2(640, 400))
	var column := _column(_modal)
	var lines := PackedStringArray()
	lines.append("NovaCore team — NASA Space Apps Challenge")
	lines.append("2D top-down colony survival for junior astronauts (7-12)")
	lines.append("")
	lines.append("Real data shipped offline: NASA CCMC DONKI, NASA OSDR RadLab")
	lines.append("(Curiosity MSL-RAD-Surface), NASA Mars Exploration, CSA.")
	lines.append("Every number in the game comes from data/nasa/*.json.")
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
