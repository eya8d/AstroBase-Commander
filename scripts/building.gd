## scripts/building.gd
## A base building that can be toggled ON/OFF.
## All stats (power, production, cost) come from buildings.json via DataLoader.
## Nothing is hard-coded — change the JSON and the game changes.
extends Area2D

## Must match an "id" in data/buildings.json.
@export var building_id: String = ""
## Whether this building starts powered on.
@export var start_on: bool = false
## Tint for the placeholder sprite so each type looks different.
## WHY: defaults to white so real sprites show their natural colors.
##       Set to a tint if you want to recolor a sprite.
@export var visual_color: Color = Color(1.0, 1.0, 1.0, 1.0)

# --- State ---
var _data: Dictionary = {}          # row from buildings.json
var _is_on: bool = false
var _forced_off: bool = false       # true when the Sol processor shut us down
var activation_tick: int = 0        # lower = activated earlier = higher priority

# Shared counter across all buildings so we know the activation order.
static var _next_activation_tick: int = 0

@onready var visual: Sprite2D = $Visual
@onready var state_label: Label = $StateLabel
@onready var info_label: Label = $InfoLabel


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("buildings")
	_load_data()

	if visual:
		visual.modulate = visual_color

	_is_on = start_on
	if _is_on:
		_next_activation_tick += 1
		activation_tick = _next_activation_tick

	info_label.visible = false
	_update_labels()


func _load_data() -> void:
	var buildings: Array = DataLoader.get_buildings()
	for b: Dictionary in buildings:
		if b.get("id", "") == building_id:
			_data = b
			return
	push_warning("Building '%s': no matching entry in buildings.json" % building_id)


# ==================== Interaction interface ====================
# Called by the player's unified interaction system.

func interact(_player: Node) -> void:
	_is_on = not _is_on
	_forced_off = false
	if _is_on:
		_next_activation_tick += 1
		activation_tick = _next_activation_tick
	EventBus.building_toggled.emit(building_id, _is_on)
	_update_labels()
	print("Building '%s' toggled → %s" % [building_id, "ON" if _is_on else "OFF"])


func show_prompt() -> void:
	info_label.visible = true


func hide_prompt() -> void:
	info_label.visible = false


# ==================== Sol-processing interface ====================
# Called by the temporary Sol clock in main_debug.gd each Sol.

func is_on() -> bool:
	return _is_on


func get_power_per_sol() -> int:
	return int(_data.get("power_per_sol", 0))


func get_produces() -> Dictionary:
	var p: Variant = _data.get("produces", {})
	if p is Dictionary:
		return p
	return {}


## Build the full cost dictionary for one Sol:
##   energy = abs(power_per_sol)  +  anything in "consumes".
func get_sol_cost() -> Dictionary:
	var cost: Dictionary = {}
	var power: int = absi(get_power_per_sol())
	if power > 0:
		cost["energy"] = power
	var consumes: Variant = _data.get("consumes", {})
	if consumes is Dictionary:
		for key: String in consumes:
			cost[key] = int(consumes[key])
	return cost


## Called by the Sol processor when this building cannot pay its cost.
func force_shutdown() -> void:
	_is_on = false
	_forced_off = true
	EventBus.building_toggled.emit(building_id, false)
	_update_labels()


## How much shield decays per Sol while this building is ON.
## Only the shield_generator has a value > 0.
func get_shield_decay_per_sol() -> int:
	return int(_data.get("shield_decay_per_sol", 0))


## Direct setter (e.g. for future systems that enable/disable buildings).
func set_on(value: bool) -> void:
	_is_on = value
	if _is_on:
		_forced_off = false
		_next_activation_tick += 1
		activation_tick = _next_activation_tick
	_update_labels()


# ==================== Labels ====================

func _update_labels() -> void:
	# --- State label (always visible, small text above the building) ---
	if state_label:
		if _forced_off:
			state_label.text = "OFF [!]"
			state_label.add_theme_color_override("font_color", Color.RED)
		elif _is_on:
			state_label.text = "ON"
			state_label.add_theme_color_override("font_color", Color.GREEN)
		else:
			state_label.text = "OFF"
			state_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))

	# --- Info label (only visible when the player is nearby) ---
	if info_label:
		var dname: String = _data.get("display_name", building_id)
		var power: int = get_power_per_sol()
		var power_str: String = ("+%d" % power) if power > 0 else str(power)
		var state_str: String = "ON" if _is_on else "OFF"
		var desc: String = _data.get("description", "")
		var teaches: String = _data.get("teaches", "")
		info_label.text = "%s [%s]\nPower: %s / Sol\n%s\n\n%s\n[E] Toggle" % [
			dname, state_str, power_str, desc, teaches
		]
