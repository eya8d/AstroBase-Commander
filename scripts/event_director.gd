## scripts/event_director.gd
## Selects short educational hazards and archived NASA space-weather events.
## Event content and balancing values stay in JSON data files.
## WHY class_name: so main_debug.gd can reference this type with @onready.
##
## Adapted from friend's delivery #2.  Changes:
##   - Added WHY comments throughout.
##   - NASA events get gameplay defaults from data/event_thresholds.json
##     (NOT hard-coded, NOT derived from NASA measurements).
class_name EventDirector
extends Node

signal event_started(event: Dictionary)
signal event_finished(result: Dictionary)

@export_range(1, 100, 1) var event_chance_percent: int = 35

var _random := RandomNumberGenerator.new()
var _events: Array[Dictionary] = []
var _active_event: Dictionary = {}
var _sols_remaining: int = 0
## WHY: gameplay defaults for NASA events that lack shield/oxygen values.
##       Loaded from data/event_thresholds.json so nothing is hard-coded.
var _radiation_defaults: Dictionary = {}


func _ready() -> void:
	_random.randomize()
	_load_thresholds()
	_load_events()


## Called after a Sol's resource processing.  A new warning then gives the
## player until the next Sol to choose which buildings to power.
func on_sol_completed(day: int) -> void:
	# --- Tick down active event ---
	if not _active_event.is_empty():
		_sols_remaining -= 1
		if _sols_remaining <= 0:
			_finish_active_event(day)

	# --- Possibly start a new event ---
	if not _active_event.is_empty() or _events.is_empty():
		return
	if _random.randi_range(1, 100) > event_chance_percent:
		return

	var chosen_event: Dictionary = _choose_event()
	if chosen_event.is_empty():
		return
	_active_event = chosen_event
	_sols_remaining = maxi(1, int(_active_event.get("duration_sols", 1)))
	event_started.emit(_active_event.duplicate(true))

	# WHY: archived NASA events also emit the shared contract signal
	#       so any system (HUD, shield) can react to real space weather.
	if bool(_active_event.get("archived_nasa_data", false)):
		EventBus.space_weather_warning.emit(_active_event.duplicate(true))


## Returns a copy of the currently active event, or {} if none.
func get_active_event() -> Dictionary:
	return _active_event.duplicate(true)


## Loads gameplay thresholds from data/event_thresholds.json.
## These are GAME BALANCE values, NOT scientific measurements.
func _load_thresholds() -> void:
	var data: Variant = DataLoader.load_json(
		"res://data/event_thresholds.json", {}
	)
	if data is Dictionary:
		var defaults: Variant = data.get("radiation_warning_defaults", {})
		if defaults is Dictionary:
			_radiation_defaults = defaults
	if _radiation_defaults.is_empty():
		push_warning("EventDirector: event_thresholds.json missing or empty — radiation events will lack gameplay values.")


## Loads events from data/events.json and merges NASA records from
## data/nasa/solar_events.json + data/nasa/radiation.json.
func _load_events() -> void:
	# --- Step 1: Authored gameplay events ---
	# WHY: DataLoader.load_json() handles missing/corrupt files safely.
	var random_data: Variant = DataLoader.load_json("res://data/events.json", [])
	if random_data is Array:
		for item: Variant in random_data:
			if item is Dictionary and not str(item.get("id", "")).is_empty():
				_events.append(item.duplicate(true))

	# --- Step 2: Archived NASA events ---
	# WHY: we merge solar_events.json into the event pool so real
	#       NASA events fire alongside gameplay events.
	var solar_data: Array = DataLoader.get_solar_events()
	var radiation_data: Array = DataLoader.get_radiation()
	for record: Dictionary in solar_data:
		var event: Dictionary = record.duplicate(true)
		event["id"] = str(event.get("id", event.get("event_id", "")))
		# WHY: only set type if the record doesn't already specify one.
		if str(event.get("type", "")).is_empty():
			event["type"] = "radiation_warning"
		event["archived_nasa_data"] = true
		event["radiation_records"] = _get_related_radiation_records(
			radiation_data, str(event.get("event_id", event.get("id", "")))
		)
		# WHY: NASA events need shield_needed and oxygen_penalty for
		#       the gameplay radiation check.  These come from
		#       event_thresholds.json — they are GAME BALANCE values,
		#       NOT derived from the NASA dose-rate measurements.
		if not event.has("shield_needed"):
			event["shield_needed"] = int(_radiation_defaults.get("shield_needed", 0))
		if not event.has("oxygen_penalty"):
			event["oxygen_penalty"] = int(_radiation_defaults.get("oxygen_penalty", 0))
		if not str(event.get("id", "")).is_empty():
			_events.append(event)

	print("EventDirector: loaded %d events (%d from events.json, %d from NASA)." % [
		_events.size(),
		_events.size() - solar_data.size(),
		solar_data.size()
	])


## Returns radiation records linked to an event by event_id.
func _get_related_radiation_records(records: Array, event_id: String) -> Array[Dictionary]:
	var related: Array[Dictionary] = []
	for item: Variant in records:
		if item is Dictionary and str(item.get("event_id", "")) == event_id:
			related.append(item.duplicate(true))
	return related


## Weighted random selection: events with higher chance_weight fire more often.
func _choose_event() -> Dictionary:
	var total_weight: int = 0
	for event: Dictionary in _events:
		total_weight += maxi(0, int(event.get("chance_weight", 0)))
	if total_weight <= 0:
		return {}

	var roll: int = _random.randi_range(1, total_weight)
	for event: Dictionary in _events:
		roll -= maxi(0, int(event.get("chance_weight", 0)))
		if roll <= 0:
			return event.duplicate(true)
	return {}


## Ends the active event, emits result, and for NASA events also emits
## space_weather_resolved on EventBus.
func _finish_active_event(day: int) -> void:
	var result: Dictionary = {
		"event_id": str(_active_event.get("id", "")),
		"day": day,
		"archived_nasa_data": bool(_active_event.get("archived_nasa_data", false)),
		"radiation_records": _active_event.get("radiation_records", []).duplicate(true)
	}
	if bool(result["archived_nasa_data"]):
		EventBus.space_weather_resolved.emit(result.duplicate(true))
	event_finished.emit(result)
	_active_event.clear()
	_sols_remaining = 0
