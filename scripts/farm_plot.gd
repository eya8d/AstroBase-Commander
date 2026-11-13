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

# State colors so you can see what's happening at a glance.
const COLOR_EMPTY    := Color(0.4, 0.25, 0.1)     # brown dirt
const COLOR_GROWING  := Color(0.2, 0.6, 0.2)      # green sprout
const COLOR_READY    := Color(0.5, 0.9, 0.2)      # bright lime — harvest me!
const COLOR_WITHERED := Color(0.5, 0.5, 0.5)      # gray — dead crop

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


func show_prompt() -> void:
	info_label.visible = true
	_update_info_label()


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
		info_label.text = "Need %d water for %s!\n[E] Try next crop" % [
			int(crop.get("water_needed", 0)), crop.get("name", "?")
		]
		_selected_crop_index = (_selected_crop_index + 1) % _all_crops.size()


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

	# WHY: color-coded so the player can see each state at a glance
	#       even without reading the label text.
	if visual:
		match _state:
			PlotState.EMPTY:
				visual.modulate = COLOR_EMPTY
			PlotState.GROWING:
				visual.modulate = COLOR_GROWING
			PlotState.READY:
				visual.modulate = COLOR_READY
			PlotState.WITHERED:
				visual.modulate = COLOR_WITHERED


func _update_labels() -> void:
	# --- State label: always visible, short text above the plot ---
	if state_label:
		match _state:
			PlotState.EMPTY:
				state_label.text = "EMPTY"
				state_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			PlotState.GROWING:
				if _is_greenhouse_powered():
					state_label.text = "GROWING (%d Sol)" % _sols_left
					state_label.add_theme_color_override("font_color", Color.GREEN)
				else:
					state_label.text = "PAUSED (%d Sol)" % _sols_left
					state_label.add_theme_color_override("font_color", Color.YELLOW)
			PlotState.READY:
				state_label.text = "READY!"
				state_label.add_theme_color_override("font_color", Color(0.5, 0.9, 0.2))
			PlotState.WITHERED:
				state_label.text = "WITHERED"
				state_label.add_theme_color_override("font_color", Color.RED)

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
				info_label.text = "Plant: %s\nWater: %d\nGrow: %d Sol\nFood: +%d\n[E] Plant" % [
					crop.get("name", "?"),
					int(crop.get("water_needed", 0)),
					int(crop.get("grow_sols", 0)),
					int(crop.get("food_yield", 0)),
				]
		PlotState.GROWING:
			var crop_name: String = _current_crop.get("name", "?")
			if _is_greenhouse_powered():
				info_label.text = "%s — growing\n%d Sol left" % [crop_name, _sols_left]
			else:
				info_label.text = "%s — PAUSED!\nGreenhouse is OFF!\n%d Sol left" % [
					crop_name, _sols_left
				]
		PlotState.READY:
			var crop_name: String = _current_crop.get("name", "?")
			var food: int = int(_current_crop.get("food_yield", 0))
			info_label.text = "%s — READY!\n+%d food\n[E] Harvest" % [crop_name, food]
		PlotState.WITHERED:
			info_label.text = "Crop withered!\nGreenhouse OFF\ntoo long.\n[E] Clear"
