## scripts/farm_plot.gd
## A farm plot where the player can plant, grow, and harvest crops.
## Growth depends on the Greenhouse being powered — no power = no growth.
## If the Greenhouse stays OFF for 2 Sols in a row, the crop withers.
## All crop data comes from crops.json via DataLoader — nothing hard-coded.
extends Area2D

enum PlotState { EMPTY, GROWING, READY, WITHERED }

# --- Internal state ---
var _state: int = PlotState.EMPTY
var _current_crop: Dictionary = {}        # crop row from crops.json
var _sols_left: int = 0                   # Sols remaining until harvest
var _greenhouse_off_sols: int = 0         # consecutive Sols without a powered Greenhouse
var _selected_crop_index: int = 0         # which crop the player will plant next
var _all_crops: Array = []                # cached from DataLoader

## Track which facts have already been unlocked (shared across ALL plots).
## Using Dictionary as a Set — keys are fact_id strings.
static var _unlocked_fact_ids: Dictionary = {}

# The plot is drawn in code (no crop art in the pack): a metal planter with soil
# furrows, sprouts that grow with the crop, a full bed when ready, dry stalks when
# withered.  Colours tell the state at a glance even without reading the tag.
const BED_SIZE := Vector2(54, 46)
const COLOR_FRAME := Color(0.36, 0.37, 0.4)
const COLOR_FRAME_DARK := Color(0.2, 0.21, 0.24)
const COLOR_SOIL := Color(0.4, 0.23, 0.13)
const COLOR_FURROW := Color(0.27, 0.15, 0.08)
const COLOR_RIDGE := Color(0.5, 0.31, 0.18)
const COLOR_SPROUT := Color(0.38, 0.8, 0.32)
const COLOR_PAUSED := Color(0.8, 0.74, 0.32)
const COLOR_LEAF := Color(0.3, 0.68, 0.26)
const COLOR_CROP := Color(0.92, 0.76, 0.42)
const COLOR_DRY := Color(0.5, 0.44, 0.36)
const LABEL_FONT_SIZE := 7
const INFO_WIDTH := 132.0

@onready var visual: Sprite2D = $Visual
@onready var state_label: Label = $StateLabel
@onready var info_label: Label = $InfoLabel


func _ready() -> void:
	# WHY: two groups — "interactable" for the player's unified interaction,
	#       "farm_plots" so other systems can find all plots easily.
	add_to_group("interactable")
	add_to_group("farm_plots")

	# Load crop definitions once.
	_all_crops = DataLoader.get_crops()
	_validate_crops()

	# Listen for Sol ticks (growth) — greenhouse state checked each tick.
	EventBus.day_changed.connect(_on_day_changed)

	# Each plot starts on a different crop from crops.json (Plot1 potato, Plot2 lettuce...).
	var digit: String = String(name).right(1)
	if digit.is_valid_int() and not _all_crops.is_empty():
		_selected_crop_index = (int(digit) - 1) % _all_crops.size()
	if visual:
		visual.visible = false
	UiRegions.style_world_label(state_label, LABEL_FONT_SIZE, true)
	UiRegions.style_world_label(info_label, LABEL_FONT_SIZE, true)
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	info_label.visible = false
	_set_state(PlotState.EMPTY)


## Warn in the Output panel if a crop entry is missing a required field.
func _validate_crops() -> void:
	var required: Array = ["id", "name", "grow_sols", "water_needed", "food_yield", "fact_id"]
	for crop: Dictionary in _all_crops:
		for field: String in required:
			if not crop.has(field):
				push_warning("FarmPlot: crop '%s' is missing field '%s'" % [
					crop.get("id", "???"), field
				])


# ==================== Interaction interface ====================
# Called by the player's unified interaction system (same as buildings).

func interact(_player: Node) -> void:
	match _state:
		PlotState.EMPTY:
			_try_plant()
		PlotState.GROWING:
			# Just show info — nothing to do while the crop is growing.
			_show_growing_info()
		PlotState.READY:
			_harvest()
		PlotState.WITHERED:
			_clear_plot()


## Details go to the HUD card above the E prompt; the plot keeps its status tag.
func show_prompt() -> void:
	_update_info_label()


func get_interaction_text() -> String:
	var crop_name: String = "FARM PLOT"
	return "%s\n%s" % [crop_name, info_label.text] if info_label else ""


func hide_prompt() -> void:
	info_label.visible = false


# ==================== Planting ====================

func _try_plant() -> void:
	if _all_crops.is_empty():
		info_label.text = "No crops available!"
		return

	var crop: Dictionary = _all_crops[_selected_crop_index]
	var water_cost: Dictionary = {"water": int(crop.get("water_needed", 0))}

	if ResourceManager.spend(water_cost):
		# WHY: spend() is atomic — it already checked and deducted.
		_current_crop = crop
		_sols_left = int(crop.get("grow_sols", 3))
		_greenhouse_off_sols = 0
		_set_state(PlotState.GROWING)
		print("Planted '%s' — needs %d Sols to grow." % [
			crop.get("name", "?"), _sols_left
		])
	else:
		# Cannot afford — show error and cycle to the next crop so
		# the player can try a cheaper one by pressing E again.
		info_label.text = "Need %d water for %s.\n[E] Try the next crop" % [
			int(crop.get("water_needed", 0)), crop.get("name", "?")
		]
		_selected_crop_index = (_selected_crop_index + 1) % _all_crops.size()
		_place_labels()


func _show_growing_info() -> void:
	# Pressing E while growing just refreshes the info label.
	_update_info_label()


# ==================== Growth (Sol-based) ====================

func _on_day_changed(_day: int) -> void:
	# Only GROWING plots care about Sol ticks.
	if _state != PlotState.GROWING:
		return

	if _is_greenhouse_powered():
		# Greenhouse is ON → crop grows one Sol.
		_greenhouse_off_sols = 0
		_sols_left -= 1
		if _sols_left <= 0:
			_set_state(PlotState.READY)
			print("Crop '%s' is ready to harvest!" % _current_crop.get("name", "?"))
		else:
			_update_labels()
			queue_redraw()
	else:
		# Greenhouse is OFF → growth pauses, wither counter ticks up.
		_greenhouse_off_sols += 1
		if _greenhouse_off_sols >= 2:
			# WHY: 2 consecutive Sols without greenhouse = crop dies.
			_set_state(PlotState.WITHERED)
			print("Crop '%s' withered — Greenhouse OFF too long!" % [
				_current_crop.get("name", "?")
			])
		else:
			_update_labels()


## Returns true if ANY building with id "greenhouse" is currently ON.
func _is_greenhouse_powered() -> bool:
	var buildings: Array = get_tree().get_nodes_in_group("buildings")
	for b: Node in buildings:
		if b.building_id == "greenhouse" and b.is_on():
			return true
	return false


# ==================== Harvesting ====================

func _harvest() -> void:
	var food: int = int(_current_crop.get("food_yield", 1))
	var crop_id: String = _current_crop.get("id", "unknown")

	ResourceManager.add("food", food)
	EventBus.crop_harvested.emit(crop_id, food)
	print("Harvested '%s' → +%d food" % [_current_crop.get("name", "?"), food])

	# Unlock the matching fact from facts.json (first time only).
	var fact_id: String = _current_crop.get("fact_id", "")
	if fact_id != "" and not _unlocked_fact_ids.has(fact_id):
		_unlocked_fact_ids[fact_id] = true
		var fact: Dictionary = _find_fact(fact_id)
		EventBus.fact_unlocked.emit(fact)
		print("Fact unlocked: %s" % fact.get("title", fact_id))

	_current_crop = {}
	_set_state(PlotState.EMPTY)


## Search facts.json for a fact with the given id.
## Returns a placeholder if not found — never crashes.
func _find_fact(fact_id: String) -> Dictionary:
	var facts: Array = DataLoader.get_facts()
	for f: Dictionary in facts:
		if f.get("id", "") == fact_id:
			return f
	# WHY: safe fallback so a missing facts.json doesn't break the game.
	push_warning("FarmPlot: fact '%s' not found in facts.json — using placeholder." % fact_id)
	return {
		"id": fact_id,
		"title": fact_id,
		"text": "Interesting fact about this crop!",
		"placeholder": true
	}


# ==================== Clear withered plot ====================

func _clear_plot() -> void:
	_current_crop = {}
	_greenhouse_off_sols = 0
	_set_state(PlotState.EMPTY)
	print("Withered crop cleared.")


# ==================== State & Labels ====================

func _set_state(new_state: int) -> void:
	_state = new_state
	_update_labels()
	queue_redraw()


func _draw() -> void:
	var half: Vector2 = BED_SIZE * 0.5
	var outer := Rect2(-half, BED_SIZE)
	draw_rect(Rect2(outer.position + Vector2(0, 2), outer.size), Color(0, 0, 0, 0.35))
	draw_rect(outer, COLOR_FRAME_DARK)
	draw_rect(outer.grow(-1.0), COLOR_FRAME)
	var soil: Rect2 = outer.grow(-4.0)
	draw_rect(soil, COLOR_SOIL)
	var rows: int = 4
	var row_h: float = soil.size.y / float(rows)
	for r: int in rows:
		var y: float = soil.position.y + row_h * (float(r) + 0.5)
		draw_line(Vector2(soil.position.x + 2, y), Vector2(soil.end.x - 2, y), COLOR_FURROW, 2.0)
		draw_line(Vector2(soil.position.x + 2, y + 2), Vector2(soil.end.x - 2, y + 2), COLOR_RIDGE, 1.0)
	if _state == PlotState.EMPTY:
		return
	var grow_total: float = maxf(1.0, float(_current_crop.get("grow_sols", 1)))
	var progress: float = 1.0
	if _state == PlotState.GROWING:
		progress = clampf(1.0 - float(_sols_left) / grow_total, 0.0, 1.0)
	var paused: bool = _state == PlotState.GROWING and not _is_greenhouse_powered()
	var cols: int = 5
	for r: int in rows:
		var y: float = soil.position.y + row_h * (float(r) + 0.5)
		for c: int in cols:
			var x: float = soil.position.x + soil.size.x * (float(c) + 0.5) / float(cols)
			var base := Vector2(x, y)
			match _state:
				PlotState.GROWING:
					var h: float = 2.0 + 4.0 * progress
					var col: Color = COLOR_PAUSED if paused else COLOR_SPROUT
					draw_line(base, base - Vector2(0, h), col.darkened(0.2), 1.0)
					draw_circle(base - Vector2(1.5, h), 1.0 + progress, col)
					draw_circle(base - Vector2(-1.5, h - 0.5), 1.0 + progress, col)
				PlotState.READY:
					draw_circle(base - Vector2(0, 3), 3.4, COLOR_LEAF)
					draw_circle(base - Vector2(1.5, 4.5), 2.2, COLOR_SPROUT)
					draw_circle(base + Vector2(1.5, 0.5), 1.3, COLOR_CROP)
				PlotState.WITHERED:
					draw_line(base, base + Vector2(2, -4), COLOR_DRY, 1.0)
					draw_line(base + Vector2(2, -4), base + Vector2(4, -2), COLOR_DRY, 1.0)


func _update_labels() -> void:
	queue_redraw()
	# --- State label: always visible, short text above the plot ---
	if state_label:
		match _state:
			PlotState.EMPTY:
				state_label.text = "EMPTY PLOT"
				state_label.add_theme_color_override("font_color", Color(0.78, 0.8, 0.84))
			PlotState.GROWING:
				if _is_greenhouse_powered():
					state_label.text = "GROWING · %d SOL" % _sols_left
					state_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.55))
				else:
					state_label.text = "PAUSED · %d SOL" % _sols_left
					state_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))
			PlotState.READY:
				state_label.text = "READY!"
				state_label.add_theme_color_override("font_color", Color(0.5, 0.9, 0.2))
			PlotState.WITHERED:
				state_label.text = "WITHERED"
				state_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))

	_update_info_label()


func _update_info_label() -> void:
	if not info_label:
		return

	match _state:
		PlotState.EMPTY:
			if _all_crops.is_empty():
				info_label.text = "No crops loaded."
			else:
				var crop: Dictionary = _all_crops[_selected_crop_index]
				info_label.text = "%s: -%d water, %d Sols, +%d food\n[E] Plant" % [
					str(crop.get("name", "?")).to_upper(),
					int(crop.get("water_needed", 0)),
					int(crop.get("grow_sols", 0)),
					int(crop.get("food_yield", 0)),
				]
		PlotState.GROWING:
			var crop_name: String = _current_crop.get("name", "?")
			if _is_greenhouse_powered():
				info_label.text = "%s is growing\n%d Sol left (greenhouse on)" % [crop_name, _sols_left]
			else:
				info_label.text = "%s paused: the greenhouse is off\n%d Sol left" % [
					crop_name, _sols_left
				]
		PlotState.READY:
			var crop_name: String = _current_crop.get("name", "?")
			var food: int = int(_current_crop.get("food_yield", 0))
			info_label.text = "%s is ready: +%d food\n[E] Harvest" % [crop_name, food]
		PlotState.WITHERED:
			info_label.text = "The crop withered (greenhouse off too long)\n[E] Clear the plot"
	_place_labels()


func _place_labels() -> void:
	var top: float = -BED_SIZE.y * 0.5 - 2.0
	UiRegions.place_world_label(state_label, top)
	UiRegions.place_world_label(info_label, top - state_label.size.y - 2.0, INFO_WIDTH)
