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
## Two minutes: with a 180-second Sol a panel gets dusty roughly twice a Sol, which is
## a chore the crew can actually notice instead of a permanent state.
@export_range(1.0, 3600.0, 1.0) var solar_dirty_interval_seconds: float = 120.0

# --- State ---
var _data: Dictionary = {}          # row from buildings.json
var _is_on: bool = false
var _forced_off: bool = false       # true when the Sol processor shut us down
var _solar_dirty: bool = false
var _solar_dirt_timer: float = 0.0
var activation_tick: int = 0        # lower = activated earlier = higher priority

# Shared counter across all buildings so we know the activation order.
static var _next_activation_tick: int = 0

@onready var visual: Sprite2D = $Visual
@onready var state_label: Label = $StateLabel
@onready var info_label: Label = $InfoLabel

const BUILDING_ART := {
	"solar_panel": {
		"off": "res://assets/buildings/off/solar_panel_station.png",
		"on": "res://assets/buildings/on/solar_panel_station.png",
	},
	"oxygen_generator": {
		"off": "res://assets/buildings/off/oxygen_generator_1.png",
		"on": "res://assets/buildings/on/oxygen_generator_1.png",
	},
	"shield_generator": {
		"off": "res://assets/buildings/off/oxygen_generator_2.png",
		"on": "res://assets/buildings/on/oxygen_generator_2.png",
	},
	"greenhouse": {
		"off": "res://assets/buildings/off/greenhouse.png",
		"on": "res://assets/buildings/on/greenhouse.png",
	},
	"research_lab": {
		"off": "res://assets/buildings/off/research_laboratory.png",
		"on": "res://assets/buildings/off/research_laboratory.png",
	},
	"crew_habitat": {
		"off": "res://assets/buildings/off/crew_habitat.png",
		"on": "res://assets/buildings/on/crew_habitat.png",
	},
	"water_extraction": {
		"off": "res://assets/buildings/off/water_extraction.png",
		"on": "res://assets/buildings/on/water_extraction.png",
	},
	"storage_facility": {
		"off": "res://assets/buildings/on/storage_facility.png",
		"on": "res://assets/buildings/on/storage_facility.png",
	},
}
## Pack building art sits on a 465x465 canvas with 370..427 px of content inside it.
## 0.17 renders a structure about 60..73 px wide and 54..66 px tall: it still owns its
## 50 px grid cell, but the astronaut (26x42 px) is only a little shorter than it, so
## nothing looms over the scene any more.
const BUILDING_ART_SCALE := Vector2(0.17, 0.17)
const DIRTY_SOLAR_PANEL_ART := "res://assets/buildings/dirty/solar_panel_station_dirty.png"
## The dirty sheet has a wider canvas (500 px) and 460 px of content, so it needs
## 0.17 x 427/460 to land on exactly the same on-screen width as the clean panel.
const DIRTY_SOLAR_PANEL_ART_SCALE := Vector2(0.1578, 0.1578)
const DIRTY_SOLAR_OUTPUT_MULTIPLIER := 0.5


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("buildings")
	_load_data()
	set_process(building_id == "solar_panel")
	if building_id == "solar_panel":
		# Let the test dirt timer update before the Sol processor on the same frame.
		process_priority = -1

	_is_on = start_on
	if _is_on:
		_next_activation_tick += 1
		activation_tick = _next_activation_tick
	_update_visual()

	info_label.visible = false
	_update_labels()


func _process(delta: float) -> void:
	if building_id != "solar_panel" or _solar_dirty:
		return
	_solar_dirt_timer += delta
	if _solar_dirt_timer >= solar_dirty_interval_seconds:
		_set_solar_dirty(true)
		print("Solar panel is dusty; output reduced until cleaned.")


func _load_data() -> void:
	var buildings: Array = DataLoader.get_buildings()
	for b: Dictionary in buildings:
		if b.get("id", "") == building_id:
			_data = b
			return
	push_warning("Building '%s': no matching entry in buildings.json" % building_id)


# ==================== Interaction interface ====================
# Called by the player's unified interaction system.

func interact(player: Node) -> void:
	if building_id == "solar_panel" and _solar_dirty:
		_clean_solar_panel(player)
		return

	_is_on = not _is_on
	_forced_off = false
	if _is_on:
		_next_activation_tick += 1
		activation_tick = _next_activation_tick
	EventBus.building_toggled.emit(building_id, _is_on)
	_update_visual()
	_update_labels()
	print("Building '%s' toggled → %s" % [building_id, "ON" if _is_on else "OFF"])


func _clean_solar_panel(player: Node) -> void:
	if not player.has_method("play_action_animation") or not (player is Node2D):
		return
	var player_sprite := player.get_node_or_null("Sprite2D") as AnimatedSprite2D
	if player_sprite == null:
		return
	var flip_h: bool = global_position.x < (player as Node2D).global_position.x
	var started: bool = bool(player.call("play_action_animation", &"clean_solar_panel", flip_h))
	if not started:
		return

	AudioManager.play_solar_cleaning()
	await player_sprite.animation_finished
	if not is_instance_valid(self) or not _solar_dirty:
		return
	_set_solar_dirty(false)
	print("Solar panel cleaned; full power output restored.")


func _set_solar_dirty(value: bool) -> void:
	if _solar_dirty == value:
		return
	_solar_dirty = value
	if not _solar_dirty:
		_solar_dirt_timer = 0.0
	_update_visual()
	_update_labels()


func show_prompt() -> void:
	info_label.visible = true


func hide_prompt() -> void:
	info_label.visible = false


# ==================== Sol-processing interface ====================
# Called by the temporary Sol clock in main_debug.gd each Sol.

func is_on() -> bool:
	return _is_on


func get_power_per_sol() -> int:
	var power: int = int(_data.get("power_per_sol", 0))
	if building_id == "solar_panel" and _solar_dirty:
		return maxi(0, floori(float(power) * DIRTY_SOLAR_OUTPUT_MULTIPLIER))
	return power


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
	_update_visual()
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
	_update_visual()
	_update_labels()


func _update_visual() -> void:
	if not visual:
		return

	var art: Dictionary = BUILDING_ART.get(building_id, {})
	if art.is_empty():
		visual.modulate = visual_color
		return

	var state := "on" if _is_on else "off"
	var texture_path: String = art.get(state, art.get("off", ""))
	if building_id == "solar_panel" and _solar_dirty:
		texture_path = DIRTY_SOLAR_PANEL_ART
	var art_texture := load(texture_path) as Texture2D
	if art_texture:
		visual.texture = art_texture
		visual.scale = BUILDING_ART_SCALE
		if building_id == "solar_panel" and _solar_dirty:
			visual.scale = DIRTY_SOLAR_PANEL_ART_SCALE
		visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		visual.modulate = Color.WHITE


# ==================== Labels ====================

func _update_labels() -> void:
	# --- State label (always visible, small text above the building) ---
	if state_label:
		if _forced_off:
			state_label.text = "OFF [!]"
			state_label.add_theme_color_override("font_color", Color.RED)
		elif building_id == "solar_panel" and _solar_dirty:
			state_label.text = "DIRTY"
			state_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.25))
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
		var dirty_status: String = "\nDUSTY — 50% OUTPUT" if building_id == "solar_panel" and _solar_dirty else ""
		var action_hint: String = "[E] Clean Solar Panel" if building_id == "solar_panel" and _solar_dirty else "[E] Toggle"
		info_label.text = "%s [%s]%s\nPower: %s / Sol\n%s\n\n%s\n%s" % [
			dname, state_str, dirty_status, power_str, desc, teaches, action_hint
		]
