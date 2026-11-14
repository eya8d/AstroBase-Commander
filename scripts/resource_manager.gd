## scripts/resource_manager.gd
## Every colony store, defined by data/resources.json (JSON pack) plus the world
## materials the commander gathers by hand (ore).
## All values are whole numbers: the pack treats them as gameplay abstractions.
##
## Ids: energy, oxygen, water, food, shield, science, crew_health, base_integrity,
##      crew_morale, ore.  The pack calls science "science_points"; both spellings work.
extends Node

## Emitted whenever a total changes. 'new_total' is the value after the change.
@warning_ignore("unused_signal")
signal resource_changed(type: String, new_total: int)

## Emitted when a capacity (max_amount x capacity multiplier) changes.
@warning_ignore("unused_signal")
signal capacity_changed(type: String, new_capacity: int)

const ALIASES: Dictionary = {"science_points": "science"}

## Used only if resources.json is missing.
const FALLBACK_START: Dictionary = {
	"energy": 100, "oxygen": 100, "water": 100, "food": 100, "shield": 30,
	"science": 0, "crew_health": 100, "base_integrity": 100, "crew_morale": 75, "ore": 0,
}

var _resources: Dictionary = {}
var _start: Dictionary = {}          # starting amount of the current run
var _base_max: Dictionary = {}       # max_amount from resources.json
var _capacity_multiplier: Dictionary = {}
var _defs: Dictionary = {}           # canonical id -> resources.json row


func _ready() -> void:
	_load_definitions()
	reset_to({})


func _load_definitions() -> void:
	_defs.clear()
	for row: Variant in DataLoader.get_resources_data():
		if row is Dictionary:
			var id: String = canonical(str(row.get("id", "")))
			if not id.is_empty():
				_defs[id] = row
	for id: String in FALLBACK_START:
		if not _defs.has(id):
			_defs[id] = {"id": id, "starting_amount": FALLBACK_START[id], "max_amount": 999}
	for id: String in _defs:
		_base_max[id] = int(_defs[id].get("max_amount", 999))


## "science_points" -> "science"; everything else unchanged.
func canonical(type: String) -> String:
	return str(ALIASES.get(type, type))


func has_type(type: String) -> bool:
	return _resources.has(canonical(type))


func get_ids() -> Array:
	return _resources.keys()


func get_definition(type: String) -> Dictionary:
	return _defs.get(canonical(type), {})


func get_display_name(type: String) -> String:
	return str(get_definition(type).get("display_name", canonical(type).capitalize()))


func is_critical(type: String) -> bool:
	return bool(get_definition(type).get("critical", false))


## Sol consumption from resources.json (before difficulty and modifiers).
func get_consumption_per_sol(type: String) -> int:
	return int(get_definition(type).get("consumption_per_sol", 0))


func get_start_amount(type: String) -> int:
	return int(_start.get(canonical(type), 0))


## Current cap: max_amount x capacity multiplier (battery damage etc.).
func get_capacity(type: String) -> int:
	var id: String = canonical(type)
	var base: int = int(_base_max.get(id, 999))
	return maxi(1, roundi(float(base) * float(_capacity_multiplier.get(id, 1.0))))


func set_capacity_multiplier(type: String, multiplier: float) -> void:
	var id: String = canonical(type)
	_capacity_multiplier[id] = multiplier
	capacity_changed.emit(id, get_capacity(id))
	if _resources.has(id) and int(_resources[id]) > get_capacity(id):
		_store(id, get_capacity(id))


## Ratio of the current amount to the start of the run (HUD colours, shortages).
func get_ratio(type: String) -> float:
	var start: int = get_start_amount(type)
	if start <= 0:
		return 1.0
	return float(get_amount(type)) / float(start)


## Add a positive amount (pickups, production). Negative amounts are ignored.
func add(type: String, amount: int) -> void:
	if amount <= 0:
		return
	apply_delta(type, amount)


## Signed change, clamped to 0..capacity. Returns the change actually applied.
func apply_delta(type: String, delta: int) -> int:
	var id: String = canonical(type)
	if not _resources.has(id):
		push_warning("ResourceManager.apply_delta(): unknown type '%s'" % type)
		return 0
	var before: int = int(_resources[id])
	var after: int = clampi(before + delta, 0, get_capacity(id))
	if after != before:
		_store(id, after)
	return after - before


func get_amount(type: String) -> int:
	var id: String = canonical(type)
	if not _resources.has(id):
		push_warning("ResourceManager.get_amount(): unknown type '%s'" % type)
		return 0
	return int(_resources[id])


## True only if EVERY resource in the cost is available.
func has_enough(cost: Dictionary) -> bool:
	for type: String in cost:
		var id: String = canonical(type)
		if not _resources.has(id):
			push_warning("ResourceManager.has_enough(): unknown type '%s'" % type)
			return false
		if int(_resources[id]) < int(cost[type]):
			return false
	return true


## Spend atomically: everything or nothing.
func spend(cost: Dictionary) -> bool:
	if not has_enough(cost):
		return false
	for type: String in cost:
		apply_delta(type, -int(cost[type]))
	return true


## Copy of all stores (safe to print).
func get_all() -> Dictionary:
	return _resources.duplicate()


## New run: every store goes back to its start. `start` overrides individual values
## (landing site, scenario); anything missing uses resources.json starting_amount.
func reset_to(start: Dictionary = {}) -> void:
	_capacity_multiplier.clear()
	_start.clear()
	var overrides: Dictionary = {}
	for key: String in start:
		overrides[canonical(key)] = start[key]
	for id: String in _defs:
		var amount: int = int(overrides.get(id, _defs[id].get("starting_amount", 0)))
		_start[id] = maxi(0, amount)
		_resources[id] = clampi(amount, 0, get_capacity(id))
	for id: String in _resources:
		resource_changed.emit(id, int(_resources[id]))
		capacity_changed.emit(id, get_capacity(id))


func _store(id: String, value: int) -> void:
	_resources[id] = value
	resource_changed.emit(id, value)
