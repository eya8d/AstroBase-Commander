## scripts/main_debug.gd
## Temporary main-scene script: debug display + Sol clock + power budget.
## The Sol clock and power processor will move to the Backend Lead's code.
## DELETE the Sol clock parts once the real system is in place.
extends Node2D

## How many real seconds equal one Sol (Martian day). 10 s is fast for testing.
@export var sol_seconds: float = 10.0

@onready var debug_label: Label = $UILayer/DebugLabel

var _current_sol: int = 0
var _sol_timer: float = 0.0
var _power_produced: int = 0
var _power_needed: int = 0


func _ready() -> void:
	ResourceManager.resource_changed.connect(_on_resource_changed)
	EventBus.item_collected.connect(_on_item_collected)
	EventBus.day_changed.connect(_on_day_changed)
	EventBus.crop_harvested.connect(_on_crop_harvested)
	EventBus.fact_unlocked.connect(_on_fact_unlocked)
	_refresh_label()

	var buildings: Array = DataLoader.get_buildings()
	print("DataLoader test: loaded %d building definitions." % buildings.size())
	var crops: Array = DataLoader.get_crops()
	print("DataLoader test: loaded %d crop definitions." % crops.size())


func _process(delta: float) -> void:
	_sol_timer += delta
	if _sol_timer >= sol_seconds:
		_sol_timer -= sol_seconds
		_advance_sol()


## F3 debug key: skip one Sol instantly for fast testing.
## WHY: so you don't have to wait 10 s per Sol while testing crops.
## This will be REMOVED in Section 8.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			print("DEBUG: F3 pressed — skipping to next Sol.")
			_advance_sol()
			get_viewport().set_input_as_handled()


# ==================== Sol clock ====================

func _advance_sol() -> void:
	_current_sol += 1
	EventBus.day_changed.emit(_current_sol)
	_process_buildings()
	_refresh_label()


func _process_buildings() -> void:
	var buildings: Array = get_tree().get_nodes_in_group("buildings")
	_power_produced = 0
	_power_needed = 0

	# --- Step 1: PRODUCERS add their outputs first ---
	# This puts energy into the pool BEFORE consumers try to spend it.
	for b: Node in buildings:
		if not b.is_on():
			continue
		if b.get_power_per_sol() > 0:
			_power_produced += b.get_power_per_sol()
			var produces: Dictionary = b.get_produces()
			for res_type: String in produces:
				ResourceManager.add(res_type, int(produces[res_type]))

	# --- Step 2: CONSUMERS try to spend (sorted by activation order) ---
	# Buildings turned on FIRST get priority.  If the budget runs out,
	# the LAST building turned on shuts off first.
	var consumers: Array = []
	for b: Node in buildings:
		if b.is_on() and b.get_power_per_sol() < 0:
			consumers.append(b)

	consumers.sort_custom(
		func(a: Node, b_node: Node) -> bool:
			return a.activation_tick < b_node.activation_tick
	)

	for b: Node in consumers:
		_power_needed += absi(b.get_power_per_sol())
		var cost: Dictionary = b.get_sol_cost()

		if ResourceManager.spend(cost):
			# Paid — now grant the building's production.
			var produces: Dictionary = b.get_produces()
			for res_type: String in produces:
				ResourceManager.add(res_type, int(produces[res_type]))
		else:
			# Cannot pay — force this building OFF.
			b.force_shutdown()
			print("Sol %d: '%s' shut down — cannot pay %s" % [
				_current_sol, b.building_id, cost
			])

	print("Sol %d complete — produced %d / needed %d" % [
		_current_sol, _power_produced, _power_needed
	])


# ==================== Signal callbacks ====================

func _on_resource_changed(_type: String, _new_total: int) -> void:
	_refresh_label()


func _on_item_collected(type: String, amount: int) -> void:
	print("EventBus.item_collected → %s x%d" % [type, amount])


func _on_day_changed(day: int) -> void:
	print("--- Sol %d ---" % day)


func _on_crop_harvested(crop_id: String, amount: int) -> void:
	print("EventBus.crop_harvested → %s x%d food" % [crop_id, amount])


func _on_fact_unlocked(fact: Dictionary) -> void:
	print("EventBus.fact_unlocked → %s: %s" % [
		fact.get("title", "?"), fact.get("text", "")
	])


# ==================== HUD ====================

func _refresh_label() -> void:
	if not is_instance_valid(debug_label):
		return
	var all: Dictionary = ResourceManager.get_all()
	var lines: PackedStringArray = PackedStringArray()
	lines.append("=== MARS SURVIVAL ACADEMY ===")
	lines.append("Sol: %d   (next in %.0f s)" % [_current_sol, sol_seconds - _sol_timer])
	lines.append("Power: produced %d / needed %d" % [_power_produced, _power_needed])
	lines.append("")
	for key: String in all:
		lines.append("  %s: %d" % [key.to_upper(), all[key]])
	lines.append("")
	lines.append("WASD=move  E=interact  F3=skip Sol")
	debug_label.text = "\n".join(lines)
