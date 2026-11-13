## scripts/data_loader.gd
## Loads JSON data files safely. If a file is missing or corrupt,
## it prints a warning and returns a fallback value — NEVER crashes.
extends Node

# Cache loaded data so we read each file only once.
var _cache: Dictionary = {}


## Core loader: reads a JSON file and returns the parsed result.
## If anything goes wrong, returns 'fallback' instead of crashing.
func load_json(path: String, fallback: Variant = null) -> Variant:
	# Return cached data if we already loaded this file.
	if _cache.has(path):
		return _cache[path]

	# Check the file exists.
	if not FileAccess.file_exists(path):
		push_warning("DataLoader: file not found — '%s'. Using fallback." % path)
		return fallback

	# Open and read.
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("DataLoader: cannot open '%s' (error %s). Using fallback." % [path, FileAccess.get_open_error()])
		return fallback

	var text := file.get_as_text()
	file.close()

	# Parse JSON.
	var json := JSON.new()
	var error := json.parse(text)
	if error != OK:
		push_warning("DataLoader: JSON parse error in '%s' at line %d: %s. Using fallback." % [
			path, json.get_error_line(), json.get_error_message()
		])
		return fallback

	var data: Variant = json.data
	_cache[path] = data
	return data


## Convenience getters — each returns an Array of Dictionaries (or empty array).
func get_buildings() -> Array:
	var result: Variant = load_json("res://data/buildings.json", [])
	if result is Array:
		return result
	return []


func get_crops() -> Array:
	var result: Variant = load_json("res://data/crops.json", [])
	if result is Array:
		return result
	return []


func get_solar_events() -> Array:
	var result: Variant = load_json("res://data/nasa/solar_events.json", [])
	if result is Array:
		return result
	return []


func get_radiation() -> Array:
	var result: Variant = load_json("res://data/nasa/radiation.json", [])
	if result is Array:
		return result
	return []


func get_facts() -> Array:
	var result: Variant = load_json("res://data/nasa/facts.json", [])
	if result is Array:
		return result
	return []
