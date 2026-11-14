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
var _event_time: float = 0.0

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

	_event_title = UiRegions.add_label(_event_holder, Rect2(318, 44, 724, 118), 68, ORANGE)
	_event_severity = UiRegions.add_label(_event_holder, Rect2(1026, 62, 252, 52), 26, CREAM)
	_event_message = UiRegions.add_label(_event_holder, Rect2(568, 240, 636, 130), 34, CREAM,
		HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP, true)
	_event_impact = UiRegions.add_label(_event_holder, Rect2(545, 545, 240, 70), 30, TEAL)
	_event_duration = UiRegions.add_label(_event_holder, Rect2(798, 545, 240, 70), 30, TEAL)
	_event_flux = UiRegions.add_label(_event_holder, Rect2(1058, 545, 235, 70), 30, TEAL)

	var hint := UiRegions.add_label(_event_holder, Rect2(568, 372, 636, 38), 24,
		Color(0.6, 0.75, 0.85, 0.85), HORIZONTAL_ALIGNMENT_RIGHT)
	hint.text = "click to dismiss"


func _on_event_started(event: Dictionary) -> void:
	_event_title.text = _short(str(event.get("title", "EVENT")))
	_event_message.text = _short(str(event.get("lesson", event.get("kid_text", ""))))

	var type: String = str(event.get("type", ""))
	var impact: String = "BASE SYSTEMS"
	if type == "dust_storm":
		impact = "SOLAR PANELS"
	elif type == "oxygen_leak":
		impact = "OXYGEN"
	elif type == "radiation_warning":
		impact = "CREW RADIATION"
	_event_impact.text = impact

	var duration: int = int(event.get("duration_sols", 1))
	_event_duration.text = "%d SOL%s" % [duration, "" if duration == 1 else "S"]

	# Real measured dose rate when the event is backed by archived NASA data.
	var flux: String = "n/a"
	var records: Variant = event.get("radiation_records", [])
	if records is Array and not (records as Array).is_empty():
		var peak: float = 0.0
		for record: Variant in (records as Array):
			if record is Dictionary:
				peak = maxf(peak, float(record.get("daily_mean_absorbed_dose_rate", 0.0)))
		if peak > 0.0:
			flux = "%.1f uGy/h" % peak
	elif type == "oxygen_leak":
		flux = "-%d O2/Sol" % int(event.get("oxygen_loss_per_sol", 0))
	elif type == "dust_storm":
		flux = "%d%% power" % int(round(float(event.get("power_output_multiplier", 1.0)) * 100.0))
	_event_flux.text = flux

	_event_severity.text = "SEVERITY: CLASS %d" % _severity_class(event, type)
	_event_holder.visible = true
	_event_time = 14.0


func _severity_class(event: Dictionary, type: String) -> int:
	match type:
		"radiation_warning":
			return 3
		"dust_storm":
			return 2
		"oxygen_leak":
			return 1
		_:
			return 2 if bool(event.get("archived_nasa_data", false)) else 1


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
		if event is InputEventMouseButton and event.pressed and _data_open:
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

	var events: Array = DataLoader.get_solar_events()
	var radiation: Array = DataLoader.get_radiation()
	var facts: Array = DataLoader.get_facts()
	var buildings: Array = DataLoader.get_buildings()

	var first_event: Dictionary = events[0] if not events.is_empty() else {}
	UiRegions.add_label(_data_holder, block_left, 20, CREAM,
		HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP, true).text = (
		"EVENTS LOADED: %d\nTYPE: %s\nDATE: %s\nMARS EFFECT: %s" % [
			events.size(),
			str(first_event.get("donki_type", "—")),
			str(first_event.get("date", "—")).left(10),
			str(first_event.get("mars_event_start", "—")).left(10),
		]
	)
	UiRegions.add_label(_data_holder, src_left, 15, TEAL,
		HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP, true).text = (
		"SOURCE: %s\n%s" % [str(first_event.get("source", "—")),
			str(first_event.get("source_url", "")).left(52)]
	)

	UiRegions.add_label(_data_holder, block_right, 18, CREAM,
		HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP, true).text = (
		"ARCHIVED MEASUREMENTS: %d\nINSTRUMENT: %s\nSPACECRAFT: %s\nSAMPLES: %s" % [
			radiation.size(),
			_instrument_field(radiation, "instrument"),
			_instrument_field(radiation, "spacecraft"),
			_samples_text(radiation),
		]
	)
	UiRegions.add_label(_data_holder, src_right, 15, TEAL,
		HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP, true).text = (
		"SOURCE: %s\n(retrieved %s)" % [_instrument_field(radiation, "source"),
			_instrument_field(radiation, "retrieved_date")]
	)

	UiRegions.add_label(_data_holder, block_left_low, 19, CREAM,
		HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP, true).text = _dose_text(radiation)
	UiRegions.add_label(_data_holder, src_left_low, 14, TEAL,
		HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP, true).text = (
		"RadLab daily means — absorbed dose rate,\nnot a crew health limit."
	)

	UiRegions.add_label(_data_holder, block_right_low, 18, CREAM,
		HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP, true).text = (
		"FACTS: %d\nBUILDINGS: %d\nWEATHER: %d\nMISSION: %d SOLS" % [
			facts.size(), buildings.size(), events.size(), int(GameState.target_sols)]
	)
	UiRegions.add_label(_data_holder, src_right_low, 14, TEAL,
		HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP, true).text = (
		"NovaCore team — NASA Space Apps\nAll data files ship inside the build (offline)."
	)

	var close := UiRegions.add_region_button(_data_holder, art, Rect2(703, 710, 275, 92), "CloseData")
	if close != null:
		close.pressed.connect(func() -> void: _toggle_data(false))


func _instrument_field(rows: Array, field: String) -> String:
	if rows.is_empty():
		return "—"
	var row: Dictionary = rows[0]
	for candidate: Dictionary in rows:
		if str(candidate.get(field, "")) != "":
			row = candidate
	return str(row.get(field, "—"))


func _samples_text(rows: Array) -> String:
	var total := 0
	for row: Dictionary in rows:
		total += int(row.get("sample_count", 0))
	return str(total) if total > 0 else "—"


## Every recorded daily mean with its date — the numbers the game is built on.
func _dose_text(rows: Array) -> String:
	var lines := PackedStringArray()
	for row: Dictionary in rows:
		lines.append("%s  %.2f %s" % [
			str(row.get("date", "?")),
			float(row.get("daily_mean_absorbed_dose_rate", 0.0)),
			_unit_short(str(row.get("unit", ""))),
		])
	if lines.is_empty():
		lines.append("no archived samples loaded")
	return "\n".join(lines)


func _unit_short(unit: String) -> String:
	if unit == "microgray_per_hour":
		return "uGy/h"
	return unit


func _toggle_data(force: Variant = null) -> void:
	# the pause overlay owns the modal state while it is open
	var pause_layer: Node = get_parent().get_node_or_null("PauseLayer")
	if pause_layer != null and pause_layer.has_method("is_open") and bool(pause_layer.is_open()):
		return
	_data_open = bool(force) if force != null else not _data_open
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

	var cost: Dictionary = row.get("build_cost", {}) as Dictionary
	var parts := PackedStringArray()
	for res: String in cost:
		parts.append("%d %s" % [int(cost[res]), res.to_upper()])
	var affordable: bool = ResourceManager.has_enough(cost)
	_info_cost.text = (" · ".join(parts) if not parts.is_empty() else "FREE")
	_info_cost.add_theme_color_override("font_color", CREAM if affordable else RED)

	var power: int = int(row.get("power_per_sol", 0))
	_info_energy.text = ("PRODUCES %d kW / SOL" % power) if power > 0 \
		else ("USES %d kW / SOL" % absi(power))
	_info_energy.add_theme_color_override("font_color", TEAL if power > 0 else ORANGE)

	var produces: Dictionary = row.get("produces", {}) as Dictionary
	var out_parts := PackedStringArray()
	for res: String in produces:
		out_parts.append("+%d %s / SOL" % [int(produces[res]), res.to_upper()])
	_info_output.text = " · ".join(out_parts) if not out_parts.is_empty() else "no output"
	_info_holder.visible = true


func _on_info_build() -> void:
	if _info_id.is_empty():
		return
	var menu: Node = get_parent().get_node_or_null("BuildMenuLayer")
	if menu != null and menu.has_method("start_placement"):
		menu.start_placement(_info_id)
	_info_holder.visible = false
