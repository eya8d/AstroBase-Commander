## scripts/hud_layer.gd
## The in-game HUD, assembled from the pack-v2 widget artwork
## (assets/ui/hud/*.png) instead of programmer-drawn boxes.
##
## Each widget is painted full size in its own PNG; here it is scaled down uniformly and
## the runtime numbers are written into the value slots that the cleanup pass emptied
## (see .work/scripts/polish_ui2.ps1 for those rectangles).  Because the holder is scaled,
## every rect below is in ARTWORK PIXELS and follows the art at any window size.
##
## It is a plain Node placed under Main; it builds its own CanvasLayer in _ready(), so the
## scene file only needs the node + this script.
extends Node

const ART_DIR := "res://assets/ui/hud/"
const ICON_DIR := "res://assets/ui/icons/resources/"

## Uniform size of the left HUD column (art is ~1290 px wide).
const WIDGET_SCALE := 0.26
## Column position and vertical rhythm in viewport pixels.
const DOCK_POS := Vector2(14, 14)
const ROW_GAP := 8.0

## What a full meter looks like, per resource.
const METRIC_CAPS := {"energy": 100, "oxygen": 100, "shield": 100}

const COLOR_TEXT := Color(0.94, 0.97, 1.0)
const COLOR_WARN := Color(1.0, 0.72, 0.35)
const COLOR_GOOD := Color(0.45, 0.95, 0.75)
const COLOR_BAD := Color(1.0, 0.42, 0.38)

var _layer: CanvasLayer
var _root: Control
var _sol_widget: Control
var _sol_label: Label
var _meters: Dictionary = {}          # resource -> {fill: ColorRect, label: Label}
var _power_widget: Control
var _power_fill: ColorRect
var _power_avail: Label
var _power_used: Label
var _chips: Dictionary = {}           # resource -> Label
var _prompt: Control
var _toast: Control
var _toast_label: Label
var _toast_time: float = 0.0
var _hint: Label

var _values: Dictionary = {}
var _refresh_accum: float = 0.0


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "HudCanvas"
	_layer.layer = 6
	add_child(_layer)

	_root = Control.new()
	_root.name = "HudRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_root)

	_build_sol_counter()
	_build_meters()
	_build_power_budget()
	_build_resource_chips()
	_build_prompt()
	_build_toast()
	_build_hint()

	for type: String in METRIC_CAPS:
		_values[type] = ResourceManager.get_amount(type)
	ResourceManager.resource_changed.connect(_on_resource_changed)
	EventBus.day_changed.connect(_on_day_changed)
	EventBus.item_collected.connect(_on_item_collected)
	EventBus.crop_harvested.connect(_on_crop_harvested)
	EventBus.building_placed.connect(_on_building_placed)
	EventBus.fact_unlocked.connect(_on_fact_unlocked)

	_refresh_all()
	toast("MISSION START — SURVIVE %d SOLS" % _target_sols())


# ==================== widget construction ====================

## Creates a Control whose local coordinates ARE the artwork's pixels.
func _make_widget(file_name: String, scale_v: float) -> Control:
	var texture := load(ART_DIR + file_name) as Texture2D
	if texture == null:
		return null
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	holder.scale = Vector2(scale_v, scale_v)
	holder.size = Vector2(texture.get_width(), texture.get_height())
	var view := TextureRect.new()
	view.texture = texture
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.size = holder.size
	holder.add_child(view)
	_root.add_child(holder)
	return holder


## A Label inside a widget, positioned with an artwork-pixel rect.
func _widget_label(holder: Control, rect: Rect2, font_size: int,
		color: Color = COLOR_TEXT,
		halign: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	# Same plated read-out the modal panels use, so nothing is painted over the art.
	return UiRegions.add_label(holder, rect, font_size, color, halign)


## A semi-transparent fill bar drawn inside a painted track.
func _widget_fill(holder: Control, rect: Rect2, color: Color) -> ColorRect:
	var fill := ColorRect.new()
	fill.position = rect.position
	fill.size = Vector2(0, rect.size.y)
	fill.color = color
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(fill)
	return fill


func _build_sol_counter() -> void:
	_sol_widget = _make_widget("sol_counter.png", WIDGET_SCALE)
	if _sol_widget == null:
		return
	_sol_widget.position = DOCK_POS
	# Measured on the restored art (text_runs.ps1): the painted "01 / 30" glyphs occupy
	# x 590..1105, y 70..203 (five glyph groups: 0 1 / 3 0), so the plate has to reach
	# past the bracket corners at x 1090..1105, otherwise a painted zero is still visible.
	_sol_label = _widget_label(_sol_widget, Rect2(570, 58, 556, 158), 96)


func _build_meters() -> void:
	# Painted track inside every 1292x242 meter and its right-hand value slot.
	var track := Rect2(248, 72, 676, 78)
	## Measured on the restored art: the invented read-out "[--- / ---]" over "[--- x]"
	## fills x 1036..1224, y 67..174.  The plate takes the whole box, otherwise the fake
	## numbers leak out on the right and below.
	var value := Rect2(1024, 62, 208, 120)
	var specs := [
		{"res": "energy", "file": "energy_meter.png", "color": Color(1.0, 0.8, 0.25)},
		{"res": "oxygen", "file": "oxygen_meter.png", "color": Color(0.35, 0.85, 1.0)},
		{"res": "shield", "file": "shield_meter.png", "color": Color(0.7, 0.5, 1.0)},
	]
	var y: float = DOCK_POS.y + _widget_height("sol_counter.png") + ROW_GAP
	for spec: Dictionary in specs:
		var holder := _make_widget(String(spec["file"]), WIDGET_SCALE)
		if holder == null:
			continue
		holder.position = Vector2(DOCK_POS.x, y)
		y += holder.size.y * WIDGET_SCALE + ROW_GAP
		_meters[String(spec["res"])] = {
			"fill": _widget_fill(holder, track, spec["color"]),
			# 46 art px is about the cap height of the painted "[--- / ---]" lettering.
			"label": _widget_label(holder, value, 38),
		}


func _widget_height(file_name: String) -> float:
	var texture := load(ART_DIR + file_name) as Texture2D
	if texture == null:
		return 60.0
	return float(texture.get_height()) * WIDGET_SCALE


func _build_power_budget() -> void:
	_power_widget = _make_widget("power_budget.png", WIDGET_SCALE)
	if _power_widget == null:
		return
	var y: float = DOCK_POS.y + _widget_height("sol_counter.png") + ROW_GAP
	y += 3.0 * (_widget_height("energy_meter.png") + ROW_GAP)
	_power_widget.position = Vector2(DOCK_POS.x, y)
	# Painted rows: "AVAILABLE POWER [ --- kW ]" then a track bar, then "USED POWER [ --- kW ]".
	## Measured on the restored art with .work/scripts/text_runs.ps1 (1292x318):
	##   AVAILABLE row brackets at x 646 and 824..834, fake "kW" value at y 114..150
	##   USED    row brackets at x 509 and 675..685, fake value at y 240..279
	## The plate sits between the two brackets, so the painted "[ ]" frame is kept and
	## only the invented "kW" number is replaced by the live value.
	_power_avail = _widget_label(_power_widget, Rect2(660, 104, 162, 52), 46, COLOR_GOOD)
	_power_used = _widget_label(_power_widget, Rect2(524, 232, 150, 52), 46, COLOR_WARN)
	_power_fill = _widget_fill(_power_widget, Rect2(310, 170, 900, 40), Color(0.35, 0.85, 1.0))


func _build_resource_chips() -> void:
	# Small strip under the column: what you carry (ore / water / food / science).
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.13, 0.88)
	style.border_color = Color(0.35, 0.75, 0.9, 0.75)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10.0)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)

	var chips := [
		{"res": "ore", "icon": "ore.png", "color": COLOR_TEXT},
		{"res": "water", "icon": "water.png", "color": Color(0.55, 0.85, 1.0)},
		{"res": "food", "icon": "storage.png", "color": Color(0.6, 0.95, 0.6)},
		{"res": "science", "icon": "science.png", "color": Color(0.85, 0.7, 1.0)},
	]
	for spec: Dictionary in chips:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 6)
		var icon := TextureRect.new()
		icon.texture = load(ICON_DIR + String(spec["icon"]))
		icon.custom_minimum_size = Vector2(30, 30)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		cell.add_child(icon)
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 22)
		label.add_theme_color_override("font_color", spec["color"])
		label.text = "0"
		cell.add_child(label)
		row.add_child(cell)
		_chips[String(spec["res"])] = label

	panel.position = Vector2(DOCK_POS.x, DOCK_POS.y + 372)
	panel.size = Vector2(330, 58)
	_root.add_child(panel)


func _build_prompt() -> void:
	_prompt = _make_widget("interact_prompt.png", 0.2)
	if _prompt == null:
		return
	_prompt.position = Vector2(1280 - 1292 * 0.2 - 14, 720 - 242 * 0.2 - 14)
	_prompt.visible = false


func _build_toast() -> void:
	_toast = _make_widget("notification_toast.png", 0.24)
	if _toast == null:
		return
	_toast.position = Vector2((1280 - 1292 * 0.24) * 0.5, 16)
	# Painted text area of the toast: x 230..1030, y 55..165.
	_toast_label = _widget_label(_toast, Rect2(230, 55, 800, 110), 42)
	_toast.visible = false


func _build_hint() -> void:
	_hint = Label.new()
	_hint.text = "WASD move · E interact · B build · TAB data · ESC pause · F2 debug"
	_hint.add_theme_font_size_override("font_size", 17)
	_hint.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95, 0.85))
	_hint.add_theme_color_override("font_outline_color", Color(0.03, 0.04, 0.07, 0.9))
	_hint.add_theme_constant_override("outline_size", 5)
	_hint.position = Vector2(12, 720 - 30)
	_hint.size = Vector2(700, 26)
	_root.add_child(_hint)


# ==================== signals ====================

func _on_resource_changed(type: String, new_total: int) -> void:
	_values[type] = new_total


func _on_day_changed(day: int) -> void:
	toast("SOL %d" % day, 2.2)


func _on_item_collected(type: String, amount: int) -> void:
	toast("+%d %s COLLECTED" % [amount, type.to_upper()])


func _on_crop_harvested(crop_id: String, amount: int) -> void:
	toast("%s HARVEST — +%d FOOD" % [crop_id.to_upper(), amount])


func _on_building_placed(building_id: String, _cell: Vector2i) -> void:
	toast("%s BUILT" % building_id.replace("_", " ").to_upper())


func _on_fact_unlocked(fact: Dictionary) -> void:
	toast("NEW FACT: %s" % str(fact.get("title", "Did you know?")))


func toast(text: String, seconds: float = 3.5) -> void:
	if _toast == null:
		return
	_toast_label.text = text
	_toast.visible = true
	_toast_time = seconds


# ==================== frame update ====================

func _process(delta: float) -> void:
	_refresh_accum += delta
	if _refresh_accum >= 0.1:
		_refresh_accum = 0.0
		_refresh_all()

	if _toast != null and _toast.visible:
		_toast_time -= delta
		if _toast_time <= 0.0:
			_toast.visible = false

	if _prompt != null:
		_prompt.visible = _player_can_interact()


func _player_can_interact() -> bool:
	var player: Node = get_parent().get_node_or_null("Player")
	if player == null or not player.has_method("has_interaction_target"):
		return false
	return bool(player.has_interaction_target())


func _main_controller() -> Node:
	return get_parent()


func _target_sols() -> int:
	return int(GameState.target_sols)


func _refresh_all() -> void:
	# --- Sol counter ---
	if _sol_label != null:
		var sol: int = 0
		if _main_controller().has_method("get_current_sol"):
			sol = int(_main_controller().get_current_sol())
		_sol_label.text = "%02d / %d" % [sol, _target_sols()]

	# --- meters ---
	for type: String in _meters:
		var meter: Dictionary = _meters[type]
		var value: int = int(_values.get(type, 0))
		var cap: int = maxi(METRIC_CAPS[type], 1)
		var frac: float = clampf(float(value) / float(cap), 0.0, 1.0)
		var fill: ColorRect = meter["fill"]
		fill.size = Vector2(676.0 * frac, 78.0)
		var label: Label = meter["label"]
		label.text = "%d\n%d%%" % [value, int(round(frac * 100.0))]
		label.add_theme_color_override("font_color",
			COLOR_BAD if value <= 0 else (COLOR_WARN if frac < 0.25 else COLOR_TEXT))

	# --- daily power budget (produced vs needed by the Sol processor) ---
	if _power_avail != null and _main_controller().has_method("get_power_stats"):
		var stats: Dictionary = _main_controller().get_power_stats()
		var produced: int = int(stats.get("produced", 0))
		var needed: int = int(stats.get("needed", 0))
		_power_avail.text = "%d kW" % produced
		_power_used.text = "%d kW" % needed
		var frac: float = clampf(float(needed) / float(maxi(produced, 1)), 0.0, 1.0)
		_power_fill.size = Vector2(900.0 * frac, 40.0)
		_power_fill.color = Color(0.35, 0.85, 1.0).lerp(Color(1.0, 0.35, 0.3),
			clampf((frac - 0.6) / 0.4, 0.0, 1.0))
		_power_avail.add_theme_color_override("font_color",
			COLOR_GOOD if produced >= needed else COLOR_BAD)

	# --- carried resources ---
	for type: String in _chips:
		_chips[type].text = str(int(_values.get(type, 0)))
