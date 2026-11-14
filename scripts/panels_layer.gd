## scripts/panels_layer.gd
## The three painted modal panels from pack v2, driven by real game data:
##
##  1. SOLAR STORM WARNING  (weather_alert_panel.png)  — shown whenever an event starts.
##     Non-modal: it fades out after a few seconds or on any click.
##  2. NASA DATA SOURCES    (data_sources_panel.png)   — TAB.  Pauses the game and prints
##     where every number in the mission comes from (data/nasa/*.json), which is the
##     "no number without a source" rule the team agreed on.
##  3. STRUCTURE DETAILS    (building_info_panel.png)  — shown while hovering a card in
##     the build menu; its BUILD button starts placement.
##
## All rects are artwork pixels of the cleaned PNGs (see .work/scripts/polish_ui*.ps1).
extends Node

const EVENT_ART := "res://assets/ui/panels/weather_alert_panel.png"
const DATA_ART := "res://assets/ui/panels/data_sources_panel.png"
const INFO_ART := "res://assets/ui/panels/building_info_panel.png"
const SLOT_DIR := "res://assets/ui/build_slots/"

const ORANGE := Color(1.0, 0.72, 0.35)
const TEAL := Color(0.45, 0.85, 0.95)
const CREAM := Color(0.94, 0.97, 1.0)
const RED := Color(1.0, 0.42, 0.38)

var _root: Control

# --- event briefing ---
var _event_holder: Control
var _event_title: Label
var _event_severity: Label
var _event_message: Label
var _event_impact: Label
var _event_duration: Label
var _event_flux: Label
## Covers the painted "RADIATION FLUX:" header when the event is not radiation.
var _flux_cover: ColorRect
var _flux_head: Label
var _event_time: float = 0.0
## Event that started while a story card was open; shown once the card closes.
var _pending_event: Dictionary = {}

# --- data sources ---
var _data_holder: Control
var _data_dim: ColorRect
var _data_open: bool = false

# --- structure details ---
var _info_holder: Control
var _info_art: Texture2D
var _info_icon: TextureRect
var _info_name: Label
var _info_class: Label
var _info_desc: Label
var _info_cost: Label
var _info_energy: Label
var _info_output: Label
var _info_build_name: Label
var _info_id: String = ""
## Keeps the details card open while the pointer travels from a build card onto it.
var _info_close_timer: float = -1.0
## True while the pointer sits on a card in the build menu.
var _card_hovered: bool = false


func _ready() -> void:
	var layer := CanvasLayer.new()
	# Modals pause the tree, so this node must keep receiving TAB and clicks.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer.name = "PanelsCanvas"
	layer.layer = 9
	add_child(layer)

	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_root)

	_build_event_panel()
	_build_info_panel()
	_build_data_panel()

	EventBus.game_event_started.connect(_on_event_started)
	EventBus.game_event_ended.connect(_on_event_ended)
	EventBus.build_menu_focus.connect(_on_build_focus)


func _process(delta: float) -> void:
	if not _pending_event.is_empty():
		_try_show_pending_event()
	if _event_holder.visible and _event_time > 0.0:
		_event_time -= delta
		if _event_time <= 0.0:
			_event_holder.visible = false
	if _info_close_timer > 0.0:
		# Keep the card while the pointer is inside it; hide shortly after it leaves.
		if _is_over_info_card():
			_info_close_timer = -1.0
		elif _info_close_timer > 0.0:
			_info_close_timer -= delta
			if _info_close_timer <= 0.0:
				_info_holder.visible = false
				_info_close_timer = -1.0
	elif _info_holder.visible and not _card_hovered and _info_close_timer < 0.0 \
			and not _is_over_info_card():
		_info_close_timer = 0.25


## The details card's rect on screen (the holder is scaled, so compute it by hand).
func _is_over_info_card() -> bool:
	if _info_holder == null or not _info_holder.visible:
		return false
	var rect := Rect2(_info_holder.global_position, _info_holder.size * _info_holder.scale.x)
	return rect.has_point(get_viewport().get_mouse_position())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("data_sources"):
		_toggle_data()
		get_viewport().set_input_as_handled()
	elif _event_holder.visible and event is InputEventMouseButton and event.pressed:
		_event_holder.visible = false
		get_viewport().set_input_as_handled()


# ==================== 1. event briefing ====================

func _build_event_panel() -> void:
	var art := load(EVENT_ART) as Texture2D
	if art == null:
		return
	_event_holder = UiRegions.add_artwork_panel(_root, art, 0.56)
	_event_holder.position = Vector2((1280.0 - art.get_width() * 0.56) * 0.5, 18.0)
	_event_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_event_holder.visible = false

	# The title band ends where the painted SEVERITY strip starts (x ~1020).
	_event_title = UiRegions.add_label(_event_holder, Rect2(318, 44, 700, 118), 68, ORANGE)
	_event_severity = UiRegions.add_label(_event_holder, Rect2(1026, 62, 252, 52), 26, CREAM)
	_event_message = UiRegions.add_label(_event_holder, Rect2(568, 240, 636, 130), 34, CREAM,
		HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP, true)
	_event_impact = UiRegions.add_label(_event_holder, Rect2(545, 545, 240, 70), 30, TEAL)
	_event_duration = UiRegions.add_label(_event_holder, Rect2(798, 545, 240, 70), 30, TEAL)
	_event_flux = UiRegions.add_label(_event_holder, Rect2(1058, 545, 235, 70), 30, TEAL)

	_flux_cover = ColorRect.new()
	_flux_cover.color = Color(0.07, 0.1, 0.157)
	_flux_cover.position = Vector2(1036, 520)
	_flux_cover.size = Vector2(204, 26)
	_flux_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_event_holder.add_child(_flux_cover)
	_flux_head = UiRegions.add_label(_event_holder, Rect2(1036, 518, 204, 30), 22, CREAM,
		HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, false, false)
	_flux_head.text = "EVENT EFFECT:"

	var hint := UiRegions.add_label(_event_holder, Rect2(568, 372, 636, 38), 24,
		Color(0.6, 0.75, 0.85, 0.85), HORIZONTAL_ALIGNMENT_RIGHT)
	hint.text = "click to dismiss"


## Mission sends the events.json definition (+ "title", "type", "historical_ref").
## The full decision card is the StoryDialog; this painted banner is the short status
## strip that stays on screen afterwards, so it waits until the dialog has closed.
func _on_event_started(event: Dictionary) -> void:
	_pending_event = event.duplicate(true)
	_try_show_pending_event()


func _try_show_pending_event() -> void:
	if _pending_event.is_empty() or _event_holder == null:
		return
	if _dialog_open():
		return
	var event: Dictionary = _pending_event
	_pending_event = {}
	var event_id: String = str(event.get("id", ""))
	_event_title.text = _short(str(event.get("title", event.get("name", "EVENT"))))
	_event_message.text = str(event.get("lesson", ""))
	_event_impact.text = _impact_text(event)

	var duration: int = int(event.get("duration_sols", 1))
	_event_duration.text = "%d SOL%s" % [duration, "" if duration == 1 else "S"]
	_event_flux.text = _flux_text(event, event_id)

	_event_severity.text = "SEVERITY: %s" % str(event.get("severity", "medium")).to_upper()
	_event_severity.add_theme_color_override("font_color", _severity_color(str(event.get("severity", ""))))
	var radiation: bool = event.has("requirements") or not str(event.get("historical_ref", "")).is_empty()
	_flux_cover.visible = not radiation
	_flux_head.visible = not radiation
	# Every label is fitted to its painted slot so nothing is clipped.
	_fit_font(_event_title, 68, 34)
	_fit_font(_event_message, 34, 20)
	_fit_font(_event_impact, 30, 18)
	_fit_font(_event_duration, 30, 18)
	_fit_font(_event_flux, 30, 18)
	_fit_font(_event_severity, 26, 16)
	_event_holder.visible = true
	_event_time = 9.0


## Shrinks a label's font until its text fits the label rect (wrapping labels by height).
func _fit_font(label: Label, max_size: int, min_size: int) -> void:
	var font: Font = label.get_theme_font("font")
	var size: int = max_size
	var box: Vector2 = label.size - Vector2(8, 4)
	while size > min_size:
		var need: Vector2
		if label.autowrap_mode != TextServer.AUTOWRAP_OFF:
			need = font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, box.x, size)
			need.y *= 1.08
		else:
			need = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
		if need.x <= box.x and need.y <= box.y:
			break
		size -= 2
	label.add_theme_font_size_override("font_size", size)


func _dialog_open() -> bool:
	var dialog: Node = get_parent().get_node_or_null("StoryDialog")
	return dialog != null and dialog.has_method("is_open") and bool(dialog.is_open())


## What the event touches, read from its first effect target (events.json vocabulary).
func _impact_text(event: Dictionary) -> String:
	if event.has("requirements"):
		return "CREW RADIATION"
	var effects: Variant = event.get("effects", [])
	if effects is Array and not (effects as Array).is_empty() and (effects as Array)[0] is Dictionary:
		var target: String = str(((effects as Array)[0] as Dictionary).get("target", ""))
		match target:
			"solar_panel":
				return "SOLAR PANELS"
			"oxygen", "oxygen_generator":
				return "OXYGEN"
			"water", "water_recycler":
				return "WATER"
			"greenhouse":
				return "GREENHOUSE"
			"energy":
				return "POWER"
			"base_integrity":
				return "HULL INTEGRITY"
			"science_points":
				return "SCIENCE"
	return "BASE SYSTEMS"


## Third box: the headline number. Archived NASA measurements appear only when the event
## is the scripted historical replay; a random radiation burst shows the game rule instead.
func _flux_text(event: Dictionary, event_id: String) -> String:
	if not str(event.get("historical_ref", "")).is_empty():
		var peak: float = 0.0
		for row: Dictionary in _rad_values():
			peak = maxf(peak, float(row.get("value", 0.0)))
		if peak > 0.0:
			return "RAD %.2f µGy/h" % peak
	if event.has("requirements"):
		var req: Dictionary = event.get("requirements", {}) as Dictionary
		return "SHIELD %d · E %d" % [int(req.get("shield", 0)), int(req.get("energy", 0))]
	var effects: Variant = event.get("effects", [])
	if effects is Array:
		for fx: Variant in effects:
			if not fx is Dictionary:
				continue
			var d: Dictionary = fx
			if str(d.get("property", "")) == "production_multiplier":
				return "%d%% OUTPUT" % roundi(float(d.get("value", 1.0)) * 100.0)
			if str(d.get("property", "")) == "enabled":
				return "OFFLINE"
			if d.has("value"):
				var sign_text: String = "-" if str(d.get("operation", "subtract")) == "subtract" else "+"
				return "%s%d %s" % [sign_text, int(d.get("value", 0)),
					ResourceManager.get_display_name(str(d.get("target", ""))).to_upper()]
	return "—" if event_id.is_empty() else "ACTIVE"


func _severity_color(severity: String) -> Color:
	match severity:
		"high", "critical":
			return RED
		"medium":
			return ORANGE
		_:
			return TEAL


func _on_event_ended(_event_id: String) -> void:
	_event_time = minf(_event_time, 2.0)


## The painted title band is one line, so keep briefing titles short.
func _short(text: String) -> String:
	var clean := text.strip_edges().to_upper()
	return clean.left(34)


# ==================== 2. NASA data sources ====================

func _build_data_panel() -> void:
	var art := load(DATA_ART) as Texture2D
	if art == null:
		return
	var scale_v := 0.70

	_data_dim = ColorRect.new()
	_data_dim.color = Color(0.01, 0.02, 0.05, 0.7)
	_data_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_data_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_data_dim.visible = false
	_root.add_child(_data_dim)

	_data_holder = UiRegions.add_artwork_panel(_data_dim, art, scale_v)
	# centring ran before the dim had a layout size, so place it explicitly
	_data_holder.position = (Vector2(1280, 720)
			- Vector2(art.get_width(), art.get_height()) * scale_v) * 0.5
	_data_holder.process_mode = Node.PROCESS_MODE_ALWAYS
	_data_holder.visible = false

	# clicking the dark backdrop closes the reference screen too
	_data_dim.gui_input.connect(func(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and mb.pressed and _data_open:
			_toggle_data(false)
	)

	# Four provenance blocks; headings stay painted, values are ours.
	# Boxes: left 88..522, right 560..1010; top row 192..415, bottom row 443..668.
	# Each box keeps its painted heading (y 215..252 / 465..502) and its painted icon on
	# the left, so text only ever goes to the right of the icon and under the heading.
	var block_left := Rect2(232, 258, 274, 100)
	var block_right := Rect2(700, 258, 296, 100)
	var src_left := Rect2(120, 368, 386, 40)
	var src_right := Rect2(592, 368, 404, 40)
	var block_left_low := Rect2(232, 512, 274, 96)
	var block_right_low := Rect2(700, 512, 296, 96)
	var src_left_low := Rect2(120, 618, 386, 40)
	var src_right_low := Rect2(592, 618, 404, 40)

	var donki: Array = DataLoader.get_solar_events()
	var rad: Dictionary = _rad_measurement()
	var values: Array = _rad_values()

	# --- top left: NASA CCMC DONKI space-weather record ---
	var first: Dictionary = donki[0] if not donki.is_empty() and donki[0] is Dictionary else {}
	var first_src: Dictionary = first.get("source", {}) as Dictionary if first.get("source", {}) is Dictionary else {}
	UiRegions.add_label(_data_holder, block_left, 18, CREAM,
		HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP, true).text = (
		"DONKI RECORDS: %d\nTYPE: %s (solar particles)\nWINDOW: %s → %s\nGAME EVENT: %s" % [
			donki.size(),
			str(first.get("donki_type", "—")),
			str(first.get("date_start", "—")),
			str(first.get("date_end", "—")).right(2),
			str(first.get("gameplay_event_id", "—")).replace("_", " "),
		]
	)
	UiRegions.add_label(_data_holder, src_left, 14, TEAL,
		HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP, true).text = (
		"SOURCE: %s %s\n%s" % [str(first_src.get("organization", "NASA")),
			str(first_src.get("dataset", "DONKI")).left(22),
			str(first_src.get("url", "")).replace("https://", "").left(56)]
	)

	# --- top right: Curiosity RAD measurement metadata ---
	var samples: int = 0
	for row: Dictionary in values:
		samples += int(row.get("sample_count", 0))
	UiRegions.add_label(_data_holder, block_right, 17, CREAM,
		HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP, true).text = (
		"INSTRUMENT: Curiosity RAD\nDATASET: %s\nPLACE: Gale Crater, Mars surface\nSAMPLES: %s over %d days" % [
			str(rad.get("dataset", "—")).left(30),
			str(samples) if samples > 0 else "—",
			values.size(),
		]
	)
	UiRegions.add_label(_data_holder, src_right, 14, TEAL,
		HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP, true).text = (
		"SOURCE: NASA OSDR RadLab API\nvisualization.osdr.nasa.gov/radlab"
	)

	# --- bottom left: the two archived daily means the scenario replays ---
	UiRegions.add_label(_data_holder, block_left_low, 18, CREAM,
		HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP, true).text = _dose_text(values)
	UiRegions.add_label(_data_holder, src_left_low, 13, TEAL,
		HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP, true).text = (
		"Absorbed dose rate, daily mean — NOT a crew\nhealth limit. Game damage is balance, not physics."
	)

	# --- bottom right: what the game itself is built from ---
	UiRegions.add_label(_data_holder, block_right_low, 17, CREAM,
		HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP, true).text = (
		"MARS FACTS: %d\nGAME EVENTS: %d (balance values)\nCITED SOURCES: %d\nMISSION: %d SOLS" % [
			DataLoader.get_facts().size(), DataLoader.get_events().size(),
			DataLoader.get_data_sources().size(), int(GameState.target_sols)]
	)
	UiRegions.add_label(_data_holder, src_right_low, 13, TEAL,
		HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP, true).text = (
		"NovaCore — NASA Space Apps. Every file ships\ninside the build and works offline.  [TAB] close"
	)

	var close := UiRegions.add_region_button(_data_holder, art, Rect2(703, 710, 275, 92), "CloseData")
	if close != null:
		close.pressed.connect(func() -> void: _toggle_data(false))


func _rad_measurement() -> Dictionary:
	var rad: Dictionary = DataLoader.get_radiation()
	var rows: Variant = rad.get("measurements", [])
	if rows is Array and not (rows as Array).is_empty() and (rows as Array)[0] is Dictionary:
		return (rows as Array)[0]
	return {}


func _rad_values() -> Array:
	var values: Variant = _rad_measurement().get("values", [])
	return values if values is Array else []


## Every recorded daily mean with its date — the numbers the historical scenario uses.
func _dose_text(rows: Array) -> String:
	var lines := PackedStringArray()
	var low: float = 0.0
	var high: float = 0.0
	for row: Dictionary in rows:
		var v: float = float(row.get("value", 0.0))
		lines.append("%s   %.2f µGy/h" % [str(row.get("date", "?")), v])
		lines.append("   %s" % str(row.get("role", "")))
		low = v if low <= 0.0 else minf(low, v)
		high = maxf(high, v)
	if lines.is_empty():
		return "no archived samples loaded"
	if low > 0.0:
		lines.append("peak ≈ %.1f× the background day" % (high / low))
	return "\n".join(lines)


func _toggle_data(force: Variant = null) -> void:
	if _data_holder == null:
		return
	var want: bool = bool(force) if force != null else not _data_open
	if want:
		# the pause overlay, a story card or the final report own the screen
		var pause_layer: Node = get_parent().get_node_or_null("PauseLayer")
		if pause_layer != null and pause_layer.has_method("is_open") and bool(pause_layer.is_open()):
			return
		if _dialog_open() or not GameState.mission_result.is_empty():
			return
		Mission.set_flag("player_opens_resource_panel")
	if want == _data_open:
		return
	_data_open = want
	_data_holder.visible = _data_open
	_data_dim.visible = _data_open
	get_tree().paused = _data_open


# ==================== 3. structure details ====================

func _build_info_panel() -> void:
	_info_art = load(INFO_ART) as Texture2D
	if _info_art == null:
		return
	var scale_v := 0.44
	_info_holder = UiRegions.add_artwork_panel(_root, _info_art, scale_v)
	# Left of the build dock, clear of the HUD column.
	_info_holder.position = Vector2(360.0, 20.0)
	_info_holder.visible = false

	_info_icon = TextureRect.new()
	_info_icon.position = Vector2(70, 186)
	_info_icon.size = Vector2(462, 452)
	# stay open while the pointer is over the card, so BUILD can be clicked
	_info_holder.mouse_entered.connect(func() -> void: _info_close_timer = -1.0)
	_info_holder.mouse_exited.connect(func() -> void:
		_info_close_timer = -1.0
		_info_holder.visible = false
	)
	_info_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_info_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_info_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_info_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_holder.add_child(_info_icon)

	_info_build_name = UiRegions.add_label(_info_holder, Rect2(122, 646, 306, 62), 32, TEAL)
	_info_name = UiRegions.add_label(_info_holder, Rect2(546, 164, 526, 62), 50, ORANGE)
	_info_class = UiRegions.add_label(_info_holder, Rect2(546, 220, 526, 44), 28, TEAL)
	_info_desc = UiRegions.add_label(_info_holder, Rect2(566, 266, 489, 144), 27, CREAM,
		HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP, true)
	_info_cost = UiRegions.add_label(_info_holder, Rect2(566, 464, 504, 76), 32, CREAM)
	_info_energy = UiRegions.add_label(_info_holder, Rect2(546, 532, 534, 54), 30, CREAM,
		HORIZONTAL_ALIGNMENT_LEFT)
	_info_output = UiRegions.add_label(_info_holder, Rect2(552, 618, 510, 90), 27, CREAM,
		HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_CENTER, true)

	var build := UiRegions.add_region_button(_info_holder, _info_art, Rect2(610, 712, 205, 88), "InfoBuild")
	if build != null:
		build.pressed.connect(_on_info_build)
	var cancel := UiRegions.add_region_button(_info_holder, _info_art, Rect2(838, 715, 205, 80), "InfoCancel")
	if cancel != null:
		cancel.pressed.connect(func() -> void: _info_holder.visible = false)
	var close := UiRegions.add_region_button(_info_holder, _info_art, Rect2(968, 32, 90, 82), "InfoClose")
	if close != null:
		close.pressed.connect(func() -> void: _info_holder.visible = false)


func _on_build_focus(building_id: String) -> void:
	if building_id.is_empty():
		_card_hovered = false
		# The pointer left a build card: give it a moment to reach this card.
		if _info_holder.visible:
			_info_close_timer = 0.3
		return
	_card_hovered = true
	_info_close_timer = -1.0
	var row: Dictionary = {}
	for candidate: Dictionary in DataLoader.get_buildings():
		if str(candidate.get("id", "")) == building_id:
			row = candidate
	if row.is_empty():
		_info_holder.visible = false
		return

	_info_id = building_id
	var display_name: String = str(row.get("display_name", building_id))
	_info_icon.texture = load(SLOT_DIR + building_id + ".png")
	_info_build_name.text = display_name.to_upper()
	_info_name.text = display_name.to_upper()
	_info_class.text = "%s // TIER 1" % str(row.get("category", "BASE SYSTEM")).to_upper()
	_info_desc.text = "%s\n\n%s" % [str(row.get("description", "")), str(row.get("teaches", ""))]

	var cost: Dictionary = GameState.adjust_build_cost(row.get("build_cost", {}) as Dictionary)
	var parts := PackedStringArray()
	for res: String in cost:
		parts.append("%d %s" % [int(cost[res]), res.to_upper()])
	var affordable: bool = ResourceManager.has_enough(cost)
	_info_cost.text = (" · ".join(parts) if not parts.is_empty() else "FREE")
	_info_cost.add_theme_color_override("font_color", CREAM if affordable else RED)

	# Per-Sol numbers come from systems.json (the same rules Mission runs each Sol).
	var nums: Dictionary = Mission.building_numbers(building_id)
	var produces: Dictionary = nums.get("produces", {}) as Dictionary
	var energy_out: int = int(produces.get("energy", 0))
	var energy_in: int = int(nums.get("energy_cost", 0))
	if energy_out > 0:
		_info_energy.text = "ENERGY +%d / SOL" % energy_out
	elif energy_in > 0:
		_info_energy.text = "ENERGY -%d / SOL" % energy_in
	else:
		_info_energy.text = "NO POWER DRAW"
	_info_energy.add_theme_color_override("font_color", TEAL if energy_out > 0 else ORANGE)

	var out_parts := PackedStringArray()
	for res: String in produces:
		if res == "energy":
			continue
		out_parts.append("+%d %s" % [int(produces[res]), ResourceManager.get_display_name(res).to_upper()])
	if int(nums.get("water_cost", 0)) > 0:
		out_parts.append("-%d WATER" % int(nums["water_cost"]))
	if out_parts.is_empty() and not str(nums.get("effect", "")).is_empty():
		out_parts.append(str(nums["effect"]).to_upper())
	if str(nums.get("system", "")).is_empty() and building_id == "farm_plot":
		out_parts.append("CROPS: plant, water, harvest")
	_info_output.text = (" · ".join(out_parts) + " / SOL") if not out_parts.is_empty() else "storage / support"
	_fit_font(_info_build_name, 32, 18)
	_fit_font(_info_name, 50, 28)
	_fit_font(_info_class, 28, 18)
	_fit_font(_info_desc, 27, 18)
	_fit_font(_info_cost, 32, 20)
	_fit_font(_info_energy, 30, 20)
	_fit_font(_info_output, 27, 18)
	_info_holder.visible = true


func _on_info_build() -> void:
	if _info_id.is_empty():
		return
	var menu: Node = get_parent().get_node_or_null("BuildMenuLayer")
	if menu != null and menu.has_method("start_placement"):
		menu.start_placement(_info_id)
	_info_holder.visible = false
