## scripts/building.gd
## A base structure in the world.  Its numbers come from data/systems.json (JSON pack)
## through the Mission autoload; buildings.json only supplies the name, the art and the
## build cost.  The player toggles it with E; story and event effects can lock it off.
extends Area2D

## Must match an "id" in data/buildings.json.
@export var building_id: String = ""
## Whether this building starts powered on (the mission start state may override it).
@export var start_on: bool = false
@export var visual_color: Color = Color(1.0, 1.0, 1.0, 1.0)
## Natural dust: each panel gets dusty again after a random 300..480 s (about two Sols).
@export var dust_min_seconds: float = 300.0
@export var dust_max_seconds: float = 480.0

var _data: Dictionary = {}
var _is_on: bool = false
var _stalled: bool = false
var _solar_dirty: bool = false
var _dust_timer: float = 0.0
var _dust_due: float = 400.0
var activation_tick: int = 0
static var _next_activation_tick: int = 0

@onready var visual: Sprite2D = $Visual
@onready var state_label: Label = $StateLabel
@onready var info_label: Label = $InfoLabel

const BUILDING_ART := {
	"solar_panel": {"off": "res://assets/buildings/off/solar_panel_station.png", "on": "res://assets/buildings/on/solar_panel_station.png"},
	"oxygen_generator": {"off": "res://assets/buildings/off/oxygen_generator_1.png", "on": "res://assets/buildings/on/oxygen_generator_1.png"},
	"shield_generator": {"off": "res://assets/buildings/off/oxygen_generator_2.png", "on": "res://assets/buildings/on/oxygen_generator_2.png"},
	"greenhouse": {"off": "res://assets/buildings/off/greenhouse.png", "on": "res://assets/buildings/on/greenhouse.png"},
	"research_lab": {"off": "res://assets/buildings/off/research_laboratory.png", "on": "res://assets/buildings/off/research_laboratory.png"},
	"crew_habitat": {"off": "res://assets/buildings/off/crew_habitat.png", "on": "res://assets/buildings/on/crew_habitat.png"},
	"water_extraction": {"off": "res://assets/buildings/off/water_extraction.png", "on": "res://assets/buildings/on/water_extraction.png"},
	"storage_facility": {"off": "res://assets/buildings/on/storage_facility.png", "on": "res://assets/buildings/on/storage_facility.png"},
}
## Pack art sits on a 465 px canvas; 0.17 keeps a structure about one astronaut tall.
const BUILDING_ART_SCALE := Vector2(0.17, 0.17)
const DIRTY_SOLAR_PANEL_ART := "res://assets/buildings/dirty/solar_panel_station_dirty.png"
const DIRTY_SOLAR_PANEL_ART_SCALE := Vector2(0.1578, 0.1578)
const DIRTY_SOLAR_OUTPUT_MULTIPLIER := 0.5
## World labels are seen through the zoom-2 camera: 7 px here reads as 14 px.
const LABEL_FONT_SIZE := 7
const INFO_WIDTH := 172.0


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("buildings")
	_data = DataLoader.get_building(building_id)
	if _data.is_empty():
		push_warning("Building '%s': no matching entry in buildings.json" % building_id)
	set_process(building_id == "solar_panel")
	_dust_due = randf_range(dust_min_seconds, dust_max_seconds)
	_is_on = start_on
	if _is_on:
		_next_activation_tick += 1
		activation_tick = _next_activation_tick
	UiRegions.style_world_label(state_label, LABEL_FONT_SIZE, true)
	UiRegions.style_world_label(info_label, LABEL_FONT_SIZE, true)
	if info_label:
		info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info_label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	info_label.visible = false
	if Mission.has_signal("state_changed"):
		Mission.state_changed.connect(_update_labels)
	_update_visual()
	_update_labels()


func _process(delta: float) -> void:
	if _solar_dirty:
		return
	_dust_timer += delta
	if _dust_timer >= _dust_due:
		set_dusty(true)
		EventBus.notice.emit("SOLAR PANEL DUSTY — OUTPUT HALVED")


# ==================== interaction ====================

func get_system_id() -> String:
	return Mission.system_for_building(building_id)


func interact(player: Node) -> void:
	if building_id == "solar_panel" and _solar_dirty:
		_clean_solar_panel(player)
		return
	var system_id: String = get_system_id()
	if not system_id.is_empty() and Mission.is_system_locked(system_id):
		AudioManager.play_ui_error()
		EventBus.notice.emit("LOCKED: %s" % Mission.get_lock_reason(system_id))
		return
	set_on(not _is_on)
	EventBus.building_toggled.emit(building_id, _is_on)
	Mission.state_changed.emit()


func _clean_solar_panel(player: Node) -> void:
	if not player.has_method("play_action_animation") or not (player is Node2D):
		return
	var player_sprite := player.get_node_or_null("Sprite2D") as AnimatedSprite2D
	if player_sprite == null:
		return
	var flip_h: bool = global_position.x < (player as Node2D).global_position.x
	if not bool(player.call("play_action_animation", &"clean_solar_panel", flip_h)):
		return
	AudioManager.play_solar_cleaning()
	await player_sprite.animation_finished
	if not is_instance_valid(self) or not _solar_dirty:
		return
	set_dusty(false)
	EventBus.notice.emit("SOLAR PANEL CLEANED — FULL OUTPUT")


## The details are shown by the HUD card above the E prompt (screen space, readable
## at zoom 2); the world keeps only the small status tag.
func show_prompt() -> void:
	_place_labels()


func get_interaction_text() -> String:
	return info_label.text if info_label else ""


func hide_prompt() -> void:
	info_label.visible = false


# ==================== Sol-processing interface (Mission) ====================

func is_on() -> bool:
	return _is_on


func is_dusty() -> bool:
	return _solar_dirty


func set_dusty(value: bool) -> void:
	if building_id != "solar_panel" or _solar_dirty == value:
		return
	_solar_dirty = value
	if not value:
		_dust_timer = 0.0
		_dust_due = randf_range(dust_min_seconds, dust_max_seconds)
	_update_visual()
	_update_labels()


func get_dust_multiplier() -> float:
	return DIRTY_SOLAR_OUTPUT_MULTIPLIER if _solar_dirty else 1.0


## Upgrade hook: 1.0 for the built level (no upgrade path in this build).
func get_output_ratio() -> float:
	return 1.0


func set_stalled(value: bool) -> void:
	if _stalled == value:
		return
	_stalled = value
	_update_labels()


func set_on(value: bool) -> void:
	if value and not _is_on:
		_next_activation_tick += 1
		activation_tick = _next_activation_tick
	_is_on = value
	if not value:
		_stalled = false
	_update_visual()
	_update_labels()


## Numbers shown on the label: this building's share of its system, per Sol.
func get_sol_numbers() -> Dictionary:
	var system_id: String = get_system_id()
	var sys: Dictionary = Mission.get_system_def(system_id)
	var share: float = 1.0 / float(Mission.STOCK_COUNT.get(system_id, 1))
	var out: Dictionary = {"produces": {}, "energy_cost": 0, "water_cost": 0}
	if sys.is_empty():
		return out
	out["energy_cost"] = roundi(float(sys.get("energy_cost", 0)) * share * Mission.get_multiplier(system_id, "energy_cost_multiplier"))
	out["water_cost"] = roundi(float(sys.get("water_cost", 0)) * share * Mission.get_multiplier(system_id, "water_cost_multiplier"))
	var produces: Variant = sys.get("produces", {})
	if produces is Dictionary:
		for res: String in produces:
			var m: float = share * Mission.get_multiplier(system_id, "production_multiplier")
			if system_id == "solar_panel":
				m *= GameState.get_site_modifier("solar_output", 1.0) * get_dust_multiplier()
			out["produces"][res] = roundi(float(produces[res]) * m)
	if system_id == "radiation_shield":
		out["produces"]["shield"] = int(sys.get("recharge_per_sol", 0))
	return out


# ==================== visuals ====================

func _update_visual() -> void:
	if not visual:
		return
	var art: Dictionary = BUILDING_ART.get(building_id, {})
	if art.is_empty():
		visual.modulate = visual_color
		return
	var texture_path: String = art.get("on" if _is_on else "off", art.get("off", ""))
	if building_id == "solar_panel" and _solar_dirty:
		texture_path = DIRTY_SOLAR_PANEL_ART
	var art_texture := load(texture_path) as Texture2D
	if art_texture:
		visual.texture = art_texture
		visual.scale = DIRTY_SOLAR_PANEL_ART_SCALE if (building_id == "solar_panel" and _solar_dirty) else BUILDING_ART_SCALE
		visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		visual.modulate = Color.WHITE if (_is_on or building_id == "storage_facility") else Color(0.78, 0.74, 0.72)


func _update_labels() -> void:
	if not is_inside_tree():
		return
	var system_id: String = get_system_id()
	var locked: String = Mission.get_lock_reason(system_id) if not system_id.is_empty() else ""
	if state_label:
		var text: String = "OFF"
		var color: Color = Color(0.72, 0.72, 0.72)
		if system_id.is_empty():
			text = ""
		elif not locked.is_empty():
			text = "LOCKED"
			color = Color(1.0, 0.35, 0.3)
		elif building_id == "solar_panel" and _solar_dirty:
			text = "DUSTY"
			color = Color(1.0, 0.6, 0.25)
		elif _is_on and _stalled:
			text = "NO POWER"
			color = Color(1.0, 0.35, 0.3)
		elif _is_on:
			text = "ON"
			color = Color(0.45, 1.0, 0.5)
		state_label.text = text
		state_label.visible = not text.is_empty()
		state_label.add_theme_color_override("font_color", color)
	if info_label:
		var sys: Dictionary = Mission.get_system_def(system_id)
		var dname: String = str(sys.get("name", _data.get("display_name", building_id)))
		var lines: PackedStringArray = PackedStringArray()
		lines.append("%s [%s]" % [dname.to_upper(), "ON" if _is_on else "OFF"])
		if not sys.is_empty():
			var n: Dictionary = get_sol_numbers()
			var parts: PackedStringArray = PackedStringArray()
			for res: String in n["produces"]:
				parts.append("+%d %s" % [int(n["produces"][res]), ResourceManager.get_display_name(res)])
			if int(n["energy_cost"]) > 0:
				parts.append("-%d Energy" % int(n["energy_cost"]))
			if int(n["water_cost"]) > 0:
				parts.append("-%d Water" % int(n["water_cost"]))
			var cond: String = ""
			if parts.is_empty() and sys.has("crew_health_recovery_per_sol"):
				parts.append("+%d Crew health" % int(sys.get("crew_health_recovery_per_sol", 1)))
				cond = " (morale 50+, supplies 20%+)"
			if parts.is_empty():
				parts.append(str(sys.get("effect", "")).replace("_", " "))
			lines.append("%s per Sol%s" % [", ".join(parts), cond])
			lines.append(str(sys.get("description", "")))
		else:
			lines.append(str(_data.get("description", "")))
		if building_id == "solar_panel" and _solar_dirty:
			lines.append("DUSTY — 50% OUTPUT")
		if not locked.is_empty():
			lines.append("LOCKED: %s" % locked)
			lines.append("Resolve it through the mission decisions.")
		elif building_id == "solar_panel" and _solar_dirty:
			lines.append("[E] Clean solar panel")
		elif not system_id.is_empty():
			lines.append("[E] Switch %s" % ("off" if _is_on else "on"))
		info_label.text = "\n".join(lines)
	_place_labels()


## Top edge of the visible artwork in local pixels (the pack canvases carry a margin).
func _art_top() -> float:
	if visual == null or visual.texture == null:
		return -40.0
	return visual.position.y - float(visual.texture.get_height()) * visual.scale.y * 0.5 + 8.0


## Status tag just above the artwork; the info card stacks above the tag.
func _place_labels() -> void:
	var top: float = _art_top()
	UiRegions.place_world_label(state_label, top)
	var card_bottom: float = top
	if state_label != null and state_label.visible:
		card_bottom -= state_label.size.y + 2.0
	UiRegions.place_world_label(info_label, card_bottom, INFO_WIDTH)
