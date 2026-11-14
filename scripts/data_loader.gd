## scripts/data_loader.gd
## Loads JSON data files safely. If a file is missing or corrupt it prints a warning and
## returns a fallback value — it never crashes.
##
## The AstroBase-Commander JSON pack lives in res://data/ (copied from
## AstroBase_Commander_JSON_Pack, which itself is .gdignore'd).  Load order from the
## pack README: game_config -> resources -> systems -> events -> nasa/ -> scenarios ->
## mission_progression -> achievements -> ending_rules + ui/.  preload_pack() follows it.
extends Node

const PACK_ORDER: Array[String] = [
	"res://data/game_config.json",
	"res://data/resources.json",
	"res://data/systems.json",
	"res://data/events.json",
	"res://data/nasa/solar_events.json",
	"res://data/nasa/radiation.json",
	"res://data/nasa/event_thresholds.json",
	"res://data/nasa/facts.json",
	"res://data/scenarios/scenarios.json",
	"res://data/mission_progression.json",
	"res://data/achievements.json",
	"res://data/ending_rules.json",
	"res://data/ui/victory.json",
	"res://data/ui/defeat.json",
	"res://data/data_sources.json",
	"res://data/story/campaign_30_sols.json",
]

# Cache loaded data so each file is read only once.
var _cache: Dictionary = {}


func _ready() -> void:
	preload_pack()


## Reads the whole pack in the documented order and reports what is missing.
func preload_pack() -> int:
	var loaded: int = 0
	for path: String in PACK_ORDER:
		if load_json(path, null) != null:
			loaded += 1
	print("DataLoader: JSON pack ready (%d/%d files)." % [loaded, PACK_ORDER.size()])
	return loaded


## Core loader: reads a JSON file and returns the parsed result, or `fallback`.
func load_json(path: String, fallback: Variant = null) -> Variant:
	if _cache.has(path):
		return _cache[path]
	if not FileAccess.file_exists(path):
		push_warning("DataLoader: file not found — '%s'. Using fallback." % path)
		return fallback
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("DataLoader: cannot open '%s' (error %s). Using fallback." % [path, FileAccess.get_open_error()])
		return fallback
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var error := json.parse(text)
	if error != OK:
		push_warning("DataLoader: JSON parse error in '%s' at line %d: %s. Using fallback." % [
			path, json.get_error_line(), json.get_error_message()])
		return fallback
	var data: Variant = json.data
	_cache[path] = data
	return data


func _dict(path: String) -> Dictionary:
	var result: Variant = load_json(path, {})
	return result if result is Dictionary else {}


func _array(path: String) -> Array:
	var result: Variant = load_json(path, [])
	return result if result is Array else []


## Array stored under `key` inside a Dictionary file.
func _list(path: String, key: String) -> Array:
	var value: Variant = _dict(path).get(key, [])
	return value if value is Array else []


func _by_id(rows: Array, id: String) -> Dictionary:
	for row: Variant in rows:
		if row is Dictionary and str(row.get("id", "")) == id:
			return row
	return {}


# ------------------------------------------------------------------ world data

func get_buildings() -> Array:
	return _array("res://data/buildings.json")


func get_building(building_id: String) -> Dictionary:
	return _by_id(get_buildings(), building_id)


func get_crops() -> Array:
	return _array("res://data/crops.json")


# ------------------------------------------------------------------ JSON pack

func get_game_config() -> Dictionary:
	return _dict("res://data/game_config.json")


func get_resources_data() -> Array:
	return _list("res://data/resources.json", "resources")


func get_resource_rules() -> Dictionary:
	var rules: Variant = _dict("res://data/resources.json").get("resource_rules", {})
	return rules if rules is Dictionary else {}


func get_resource_def(resource_id: String) -> Dictionary:
	return _by_id(get_resources_data(), resource_id)


func get_systems_data() -> Dictionary:
	return _dict("res://data/systems.json")


func get_systems() -> Array:
	return _list("res://data/systems.json", "systems")


func get_system(system_id: String) -> Dictionary:
	return _by_id(get_systems(), system_id)


func get_events() -> Array:
	return _list("res://data/events.json", "events")


func get_event(event_id: String) -> Dictionary:
	return _by_id(get_events(), event_id)


## NASA DONKI records (data/nasa/solar_events.json -> "events").
func get_solar_events() -> Array:
	return _list("res://data/nasa/solar_events.json", "events")


func get_solar_event(record_id: String) -> Dictionary:
	return _by_id(get_solar_events(), record_id)


## Curiosity RAD readings (data/nasa/radiation.json). Kept as the whole Dictionary so the
## unit, the event period and the per-value source URLs travel with the numbers.
func get_radiation() -> Dictionary:
	return _dict("res://data/nasa/radiation.json")


func get_radiation_measurement(measurement_id: String) -> Dictionary:
	var rows: Variant = get_radiation().get("measurements", [])
	return _by_id(rows if rows is Array else [], measurement_id)


func get_thresholds() -> Array:
	return _list("res://data/nasa/event_thresholds.json", "thresholds")


func get_threshold_for(record_id: String) -> Dictionary:
	for row: Variant in get_thresholds():
		if row is Dictionary and str(row.get("applies_to_event_id", "")) == record_id:
			return row
	return {}


func get_facts() -> Array:
	var data: Variant = load_json("res://data/nasa/facts.json", [])
	if data is Array:
		return data
	if data is Dictionary:
		var facts: Variant = (data as Dictionary).get("facts", [])
		return facts if facts is Array else []
	return []


func get_scenarios() -> Array:
	return _list("res://data/scenarios/scenarios.json", "scenarios")


func get_scenario(scenario_id: String) -> Dictionary:
	return _by_id(get_scenarios(), scenario_id)


func get_mission_progression() -> Dictionary:
	return _dict("res://data/mission_progression.json")


func get_achievements() -> Array:
	return _list("res://data/achievements.json", "achievements")


func get_ending_rules() -> Dictionary:
	return _dict("res://data/ending_rules.json")


func get_ui_screen(screen: String) -> Dictionary:
	return _dict("res://data/ui/%s.json" % screen)


func get_data_sources() -> Array:
	return _list("res://data/data_sources.json", "sources")


func get_data_source(source_id: String) -> Dictionary:
	return _by_id(get_data_sources(), source_id)


## The 30-Sol story script (data/story/campaign_30_sols.json).
func get_story(path: String = "res://data/story/campaign_30_sols.json") -> Dictionary:
	return _dict(path)


# ------------------------------------------------------------------ Day 0 landing sites

func get_landing_catalogue() -> Dictionary:
	return _dict("res://data/landing_sites.json")


func get_landing_sites() -> Array:
	var sites: Variant = get_landing_catalogue().get("sites", [])
	return sites if sites is Array else []


func get_landing_site(site_id: String) -> Dictionary:
	return _by_id(get_landing_sites(), site_id)
