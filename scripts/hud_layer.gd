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
const WIDGET_SCALE := 0.22
## Column position and vertical rhythm in viewport pixels.
const DOCK_POS := Vector2(12, 12)
const ROW_GAP := 6.0

## Colony status bars under the painted column (resources.json ids).
const STATUS_BARS := [
	{"res": "water", "label": "WATER", "color": Color(0.45, 0.8, 1.0)},
	{"res": "food", "label": "FOOD", "color": Color(0.6, 0.95, 0.5)},
	{"res": "crew_health", "label": "CREW HEALTH", "color": Color(1.0, 0.5, 0.55)},
	{"res": "crew_morale", "label": "MORALE", "color": Color(1.0, 0.8, 0.4)},
	{"res": "base_integrity", "label": "INTEGRITY", "color": Color(0.8, 0.8, 0.85)},
]

const COLOR_TEXT := Color(0.94, 0.97, 1.0)
const COLOR_WARN := Color(1.0, 0.72, 0.35)
const COLOR_GOOD := Color(0.45, 0.95, 0.75)
const COLOR_BAD := Color(1.0, 0.42, 0.38)

const OBJECTIVE_MARKS: Dictionary = {
	"done": "[color=#7CFF8A]✔[/color]", "failed": "[color=#FF6B5E]✖[/color]",
	"open": "[color=#FFD27A]○[/color]", "info": "[color=#9CC8FF]»[/color]",
}

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
var _bars: Dictionary = {}            # resource -> {fill, value, width}
var _mission_title: Label
var _mission_body: RichTextLabel
var _sol_clock: ColorRect
var _status_bottom: float = 0.0
var _prompt: Control
## Screen-space card above the E prompt: what the nearest object is and what E does.
var _interact_card: PanelContainer
var _interact_text: Label
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
	_build_status_panel()
	_build_mission_panel()
	_build_prompt()
	_build_toast()
	_build_hint()

	# Every type, not just the meters: the chips (ore / water / food / science) must show
	# the landing site's starting stores before the first change arrives.
	_values = ResourceManager.get_all()
	ResourceManager.resource_changed.connect(_on_resource_changed)
	EventBus.day_changed.connect(_on_day_changed)
	EventBus.item_collected.connect(_on_item_collected)
	EventBus.crop_harvested.connect(_on_crop_harvested)
	EventBus.building_placed.connect(_on_building_placed)
	EventBus.fact_unlocked.connect(_on_fact_unlocked)
	EventBus.notice.connect(func(text: String) -> void: toast(text, 3.0))

	_refresh_all()
	var site_name: String = GameState.get_landing_site_name()
	var title: String = str(GameState.get_scenario().get("title", "Mission"))
	if site_name.is_empty():
		toast("%s" % title.to_upper())
	else:
		toast("%s\n%s" % [site_name.to_upper(), title.to_upper()], 5.0)


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


func _panel_style(border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.07, 0.86)
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8.0)
	return style


## Colony status: water, food, crew health, morale, integrity bars + ore / science chips.
func _build_status_panel() -> void:
	var y: float = DOCK_POS.y + _widget_height("sol_counter.png") + ROW_GAP
	y += 3.0 * (_widget_height("energy_meter.png") + ROW_GAP) + _widget_height("power_budget.png") + ROW_GAP
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.85, 0.45, 0.25, 0.8)))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = Vector2(DOCK_POS.x, y)
	panel.custom_minimum_size = Vector2(284, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	panel.add_child(col)
	for spec: Dictionary in STATUS_BARS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var name_label := Label.new()
		name_label.text = String(spec["label"])
		name_label.custom_minimum_size = Vector2(92, 0)
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.add_theme_color_override("font_color", Color(0.85, 0.82, 0.78))
		row.add_child(name_label)
		var track := ColorRect.new()
		track.color = Color(0.16, 0.12, 0.12)
		track.custom_minimum_size = Vector2(124, 12)
		track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := ColorRect.new()
		fill.color = spec["color"]
		fill.size = Vector2(0, 12)
		track.add_child(fill)
		row.add_child(track)
		var value := Label.new()
		value.custom_minimum_size = Vector2(46, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.add_theme_font_size_override("font_size", 12)
		row.add_child(value)
		col.add_child(row)
		_bars[String(spec["res"])] = {"fill": fill, "value": value, "width": 124.0, "color": spec["color"]}

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	col.add_child(row)
	var chips := [
		{"res": "ore", "icon": "ore.png", "color": COLOR_TEXT},
		{"res": "science", "icon": "science.png", "color": Color(0.85, 0.7, 1.0)},
	]
	for spec: Dictionary in chips:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		var icon := TextureRect.new()
		icon.texture = load(ICON_DIR + String(spec["icon"]))
		icon.custom_minimum_size = Vector2(22, 22)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		cell.add_child(icon)
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 15)
		label.add_theme_color_override("font_color", spec["color"])
		label.text = "0"
		cell.add_child(label)
		row.add_child(cell)
		_chips[String(spec["res"])] = label
	_root.add_child(panel)


## Top-right: week / phase, objectives, what is affecting the base, Sol clock.
func _build_mission_panel() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.4, 0.75, 0.95, 0.75)))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = Vector2(1280 - 312 - 12, 12)
	panel.custom_minimum_size = Vector2(312, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	_mission_title = Label.new()
	_mission_title.add_theme_font_size_override("font_size", 13)
	_mission_title.add_theme_color_override("font_color", Color(1.0, 0.75, 0.4))
	_mission_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_mission_title)
	var clock_track := ColorRect.new()
	clock_track.color = Color(0.14, 0.14, 0.2)
	clock_track.custom_minimum_size = Vector2(296, 4)
	_sol_clock = ColorRect.new()
	_sol_clock.color = Color(0.4, 0.75, 0.95)
	_sol_clock.size = Vector2(0, 4)
	clock_track.add_child(_sol_clock)
	col.add_child(clock_track)
	_mission_body = RichTextLabel.new()
	_mission_body.bbcode_enabled = true
	_mission_body.fit_content = true
	_mission_body.scroll_active = false
	_mission_body.custom_minimum_size = Vector2(296, 0)
	_mission_body.add_theme_font_size_override("normal_font_size", 12)
	_mission_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_mission_body)
	_root.add_child(panel)


func _build_prompt() -> void:
	_prompt = _make_widget("interact_prompt.png", 0.2)
	if _prompt == null:
		return
	_prompt.position = Vector2(1280 - 1292 * 0.2 - 14, 720 - 242 * 0.2 - 14)
	_prompt.visible = false

	_interact_card = PanelContainer.new()
	_interact_card.name = "InteractCard"
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.03, 0.05, 0.08, 0.9)
	box.border_color = Color(0.45, 0.85, 0.95, 0.7)
	box.set_border_width_all(2)
	box.set_corner_radius_all(6)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	_interact_card.add_theme_stylebox_override("panel", box)
	_interact_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interact_text = Label.new()
	_interact_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_interact_text.custom_minimum_size = Vector2(300, 0)
	_interact_text.add_theme_font_size_override("font_size", 14)
	_interact_text.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	_interact_text.add_theme_constant_override("line_spacing", 2)
	_interact_card.add_child(_interact_text)
	_interact_card.visible = false
	_root.add_child(_interact_card)


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
	_hint.text = "WASD move · E interact · B build · TAB base data · ESC pause"
	if OS.is_debug_build():
		_hint.text += " · F3 skip Sol"
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95, 0.85))
	_hint.add_theme_color_override("font_outline_color", Color(0.03, 0.04, 0.07, 0.9))
	_hint.add_theme_constant_override("outline_size", 4)
	_hint.position = Vector2(12, 720 - 24)
	_hint.size = Vector2(700, 26)
	_root.add_child(_hint)


# ==================== signals ====================

func _on_resource_changed(type: String, new_total: int) -> void:
	_values[type] = new_total


func _on_day_changed(day: int) -> void:
	toast("SOL %d BEGINS" % day, 2.2)


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
		_update_interact_card()


func _update_interact_card() -> void:
	if _interact_card == null:
		return
	var text: String = ""
	if _prompt.visible:
		var player: Node = get_parent().get_node_or_null("Player")
		var target: Node = player.call("get_interaction_target") if player != null and player.has_method("get_interaction_target") else null
		if target != null and target.has_method("get_interaction_text"):
			text = str(target.call("get_interaction_text"))
	if text.is_empty():
		_interact_card.visible = false
		return
	if _interact_text.text != text or not _interact_card.visible:
		_interact_text.text = text
		_interact_card.visible = true
		_interact_card.reset_size()
		_interact_card.position = Vector2(1280.0 - 14.0 - _interact_card.size.x,
			_prompt.position.y - 8.0 - _interact_card.size.y)


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
		var cap: int = ResourceManager.get_capacity(type)
		var frac: float = clampf(float(value) / float(cap), 0.0, 1.0)
		var fill: ColorRect = meter["fill"]
		fill.size = Vector2(676.0 * frac, 78.0)
		var label: Label = meter["label"]
		label.text = "%d\n/ %d" % [value, cap]
		label.add_theme_color_override("font_color", _alert_color(type, value))

	# --- colony status ---
	for type: String in _bars:
		var bar: Dictionary = _bars[type]
		var amount: int = int(_values.get(type, 0))
		var cap_b: int = ResourceManager.get_capacity(type)
		(bar["fill"] as ColorRect).size = Vector2(float(bar["width"]) * clampf(float(amount) / float(cap_b), 0.0, 1.0), 12)
		var alert: Color = _alert_color(type, amount)
		(bar["fill"] as ColorRect).color = bar["color"] if alert == COLOR_TEXT else alert
		(bar["value"] as Label).text = "%d" % amount
		(bar["value"] as Label).add_theme_color_override("font_color", alert)

	# --- mission panel ---
	if _mission_title != null:
		var week: Dictionary = Mission.get_week()
		var phase: Dictionary = Mission.get_phase()
		var head: String = "SOL %d / %d" % [Mission.sol, _target_sols()]
		if not week.is_empty():
			head += "  ·  WEEK %d: %s" % [int(week.get("week", 0)), str(week.get("title", "")).to_upper()]
		elif not phase.is_empty():
			head += "  ·  %s" % str(phase.get("name", "")).to_upper()
		_mission_title.text = head
		if _main_controller().has_method("get_sol_progress"):
			_sol_clock.size = Vector2(296.0 * float(_main_controller().get_sol_progress()), 4)
		var lines: PackedStringArray = PackedStringArray()
		for o: Dictionary in Mission.get_objective_lines():
			var mark: String = str(OBJECTIVE_MARKS.get(str(o["state"]), "·"))
			lines.append("%s %s" % [mark, str(o["text"])])
		var active: Array = Mission.get_active_labels()
		if not active.is_empty():
			lines.append("[color=#FF9A6B]ACTIVE:[/color] %s" % ", ".join(PackedStringArray(active.slice(0, 4))))
		_mission_body.text = "\n".join(lines)

	# --- daily power budget (produced vs needed by the Sol processor) ---
	if _power_avail != null and _main_controller().has_method("get_power_stats"):
		var stats: Dictionary = _main_controller().get_power_stats()
		var produced: int = int(stats.get("produced", 0))
		var needed: int = int(stats.get("needed", 0))
		# Energy is a gameplay abstraction (resources.json): units per Sol, not kW.
		_power_avail.text = "+%d" % produced
		_power_used.text = "-%d" % needed
		var frac: float = clampf(float(needed) / float(maxi(produced, 1)), 0.0, 1.0)
		_power_fill.size = Vector2(900.0 * frac, 40.0)
		_power_fill.color = Color(0.35, 0.85, 1.0).lerp(Color(1.0, 0.35, 0.3),
			clampf((frac - 0.6) / 0.4, 0.0, 1.0))
		_power_avail.add_theme_color_override("font_color",
			COLOR_GOOD if produced >= needed else COLOR_BAD)

	# --- carried resources ---
	for type: String in _chips:
		_chips[type].text = str(int(_values.get(type, 0)))


## resources.json display_thresholds: yellow below 60 %, red below 30 % of the start.
func _alert_color(type: String, value: int) -> Color:
	if value <= 0 and ResourceManager.is_critical(type):
		return COLOR_BAD
	var rules: Dictionary = DataLoader.get_resource_rules().get("display_thresholds", {})
	var ratio: float = ResourceManager.get_ratio(type)
	if ratio < float(rules.get("red_below_ratio", 0.3)):
		return COLOR_BAD
	if ratio < float(rules.get("yellow_below_ratio", 0.6)):
		return COLOR_WARN
	return COLOR_TEXT
