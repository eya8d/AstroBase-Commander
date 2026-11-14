## scripts/main_debug.gd
## Gameplay scene controller.
##   * builds the landing-site world (ground art from data/landing_sites.json, solid
##     terrain from the shared craters/spires plus the site's terrain_obstacles)
##   * runs the Sol clock and hands every Sol to the Mission rules (scripts/mission.gd)
##   * F2 debug read-out, F3 skip a Sol, F4 force a random event (testing; debug
##     builds only, so the exported release / web build has no cheat keys)
extends Node2D

## World size: the 1376x768 in-game maps drawn at 1.5x.
const MAP_SCALE := 1.5
const WORLD_SIZE := Vector2(2064, 1152)
const DEFAULT_GROUND := "res://map/acidalia_planitia_in_game_map._a_full_screen_16_9_widescreen_1920x1080_2d_top/screen.png"
## Solid terrain shared by all three maps (map pixels): craters, spires.
const SHARED_OBSTACLES: Array = [
	{"circle": [470, 75, 45]}, {"circle": [583, 190, 55]}, {"circle": [148, 615, 45]},
	{"circle": [1025, 635, 50]}, {"circle": [1040, 490, 34]}, {"circle": [1160, 420, 30]},
]

var sol_seconds: float = 90.0
var _sol_timer: float = 0.0

@onready var debug_label: Label = $UILayer/DebugLabel


func _ready() -> void:
	AudioManager.enter_gameplay()
	sol_seconds = GameState.sol_seconds
	if not GameState.mission_running:
		GameState.begin_mission()
	_build_world()
	ResourceManager.resource_changed.connect(_on_resource_changed)
	debug_label.visible = GameState.show_debug_text
	# Buildings finish their _ready first, then the run applies its start state and
	# queues the Sol card(s).
	Mission.attach_world.call_deferred()


func _process(delta: float) -> void:
	if Mission.ended or not Mission.is_world_attached():
		return
	_sol_timer += delta
	if _sol_timer >= sol_seconds:
		_sol_timer -= sol_seconds
		Mission.process_end_of_sol()
	if GameState.show_debug_text:
		_refresh_debug()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if not OS.is_debug_build():
		return
	match event.keycode:
		KEY_F2:
			GameState.show_debug_text = not GameState.show_debug_text
			debug_label.visible = GameState.show_debug_text
			get_viewport().set_input_as_handled()
		KEY_F3:
			if not Mission.ended:
				_sol_timer = 0.0
				Mission.process_end_of_sol()
			get_viewport().set_input_as_handled()
		KEY_F4:
			var ids: Array = []
			for ev: Variant in DataLoader.get_events():
				if ev is Dictionary:
					ids.append(str(ev.get("id", "")))
			if not ids.is_empty() and not Mission.ended:
				Mission.debug_trigger_event(str(ids[randi() % ids.size()]))
			get_viewport().set_input_as_handled()


# ==================== world ====================

func _build_world() -> void:
	var floor_sprite := get_node_or_null("Floor") as Sprite2D
	var path: String = GameState.get_site_ground_texture()
	if path.is_empty() or not ResourceLoader.exists(path):
		path = DEFAULT_GROUND
	var tex := load(path) as Texture2D
	if floor_sprite != null and tex != null:
		floor_sprite.texture = tex
		floor_sprite.centered = false
		floor_sprite.position = Vector2.ZERO
		floor_sprite.scale = WORLD_SIZE / Vector2(tex.get_width(), tex.get_height())
	var terrain := Node2D.new()
	terrain.name = "Terrain"
	add_child(terrain)
	var shapes: Array = SHARED_OBSTACLES.duplicate()
	var extra: Variant = GameState.landing_site.get("terrain_obstacles", [])
	if extra is Array:
		shapes.append_array(extra)
	for spec: Variant in shapes:
		if spec is Dictionary:
			_add_obstacle(terrain, spec)


## {"circle": [x, y, r]} | {"rect": [x, y, w, h]} | {"segment": [x1, y1, x2, y2, thickness]}
## in map pixels; scaled by MAP_SCALE into world space.
func _add_obstacle(parent: Node2D, spec: Dictionary) -> void:
	var body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	if spec.has("circle"):
		var c: Array = spec["circle"]
		var circle := CircleShape2D.new()
		circle.radius = float(c[2]) * MAP_SCALE
		shape.shape = circle
		body.position = Vector2(float(c[0]), float(c[1])) * MAP_SCALE
	elif spec.has("rect"):
		var r: Array = spec["rect"]
		var rect := RectangleShape2D.new()
		rect.size = Vector2(float(r[2]), float(r[3])) * MAP_SCALE
		shape.shape = rect
		body.position = (Vector2(float(r[0]), float(r[1])) + Vector2(float(r[2]), float(r[3])) * 0.5) * MAP_SCALE
	elif spec.has("segment"):
		var s: Array = spec["segment"]
		var a := Vector2(float(s[0]), float(s[1])) * MAP_SCALE
		var b := Vector2(float(s[2]), float(s[3])) * MAP_SCALE
		var capsule := RectangleShape2D.new()
		capsule.size = Vector2(a.distance_to(b), float(s[4]) * MAP_SCALE)
		shape.shape = capsule
		body.position = (a + b) * 0.5
		body.rotation = (b - a).angle()
	else:
		return
	body.add_child(shape)
	parent.add_child(body)


# ==================== accessors for the HUD / panels ====================

func get_current_sol() -> int:
	return Mission.sol


func get_sol_progress() -> float:
	return clampf(_sol_timer / maxf(sol_seconds, 1.0), 0.0, 1.0)


## Live forecast of the energy budget for this Sol (changes as buildings are toggled).
func get_power_stats() -> Dictionary:
	var produced: int = 0
	var needed: int = 0
	for b: Node in get_tree().get_nodes_in_group("buildings"):
		if not b.has_method("get_sol_numbers") or not b.is_on():
			continue
		var system_id: String = b.get_system_id()
		if system_id.is_empty() or Mission.is_system_locked(system_id):
			continue
		var n: Dictionary = b.get_sol_numbers()
		produced += int(n["produces"].get("energy", 0))
		needed += int(n["energy_cost"])
	needed += roundi(float(ResourceManager.get_consumption_per_sol("energy")) * GameState.get_resource_multiplier()
		* Mission.get_multiplier("energy", "consumption_multiplier"))
	return {"produced": produced, "needed": needed, "sol": Mission.sol, "target": int(GameState.target_sols)}


# ==================== debug ====================

func _on_resource_changed(type: String, new_total: int) -> void:
	if type == "oxygen":
		AudioManager.set_oxygen_critical(new_total > 0 and float(new_total) <= ResourceManager.get_start_amount("oxygen") * 0.25)


func _refresh_debug() -> void:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("=== ASTROBASE-COMMANDER DEBUG ===")
	lines.append("Sol %d  next in %.0f s  scenario %s  difficulty %s" % [Mission.sol, sol_seconds - _sol_timer,
		GameState.scenario_id, GameState.difficulty])
	var all: Dictionary = ResourceManager.get_all()
	for key: String in all:
		lines.append("  %s: %d / %d" % [key, int(all[key]), ResourceManager.get_capacity(key)])
	lines.append("Modifiers: %s" % ", ".join(PackedStringArray(Mission.get_active_labels())))
	lines.append("Flags: %s" % ", ".join(PackedStringArray(Mission.flags.keys())))
	lines.append("F3 skip Sol · F4 random event")
	debug_label.text = "\n".join(lines)
