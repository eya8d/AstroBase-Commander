## scripts/main_debug.gd
## Temporary main-scene script: debug display + Sol clock + power budget + events.
## The Sol clock and power processor will move to the Backend Lead's code.
## DELETE the Sol clock parts once the real system is in place.
##
## MERGE NOTES (friend delivery #2):
##   Kept from OUR version: game_event_started/ended signals, shield decay,
##     active-event HUD display, all EventBus signal callbacks.
##   Taken from FRIEND's version: EventDirector integration, EventLabel,
##     per-building dust-storm modifier, oxygen leak via oxygen_loss_per_sol,
##     NASA briefing display with RadLab readings.
##   Added: radiation shield check on event finish (player gets warning Sol
##     to prepare), shield decay runs regardless of generator ON/OFF.
extends Node2D

## How many real seconds equal one Sol (Martian day). 10 s is fast for testing.
@export var sol_seconds: float = 10.0

@onready var debug_label: Label = $UILayer/DebugLabel
@onready var event_panel: PanelContainer = $UILayer/EventPanel
@onready var event_label: Label = $UILayer/EventPanel/EventLabel
@onready var event_director: EventDirector = $EventDirector

var _current_sol: int = 0
var _sol_timer: float = 0.0
var _power_produced: int = 0
var _power_needed: int = 0
var _latest_event_notice: String = "No event yet."
var _showing_event_briefing: bool = false
## WHY: we store the full event data when it starts so we can apply
##       gameplay effects when it finishes (the director clears its copy).
var _current_event_data: Dictionary = {}


func _ready() -> void:
	AudioManager.enter_gameplay()
	# The menu flow owns the mission settings (scripts/game_state.gd).
	sol_seconds = GameState.sol_seconds
	_current_sol = 1
	if not GameState.mission_running:
		GameState.begin_mission()
	ResourceManager.resource_changed.connect(_on_resource_changed)
	EventBus.item_collected.connect(_on_item_collected)
	EventBus.day_changed.connect(_on_day_changed)
	EventBus.crop_harvested.connect(_on_crop_harvested)
	EventBus.fact_unlocked.connect(_on_fact_unlocked)
	EventBus.space_weather_warning.connect(_on_space_weather_warning)
	EventBus.space_weather_resolved.connect(_on_space_weather_resolved)
	event_director.event_started.connect(_on_event_started)
	event_director.event_finished.connect(_on_event_finished)
	_refresh_label()
	_refresh_event_label()
	# The text read-out is a debug tool now that the painted HUD exists (toggle F2).
	debug_label.visible = GameState.show_debug_text

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
## WHY: so you don't have to wait 10 s per Sol while testing crops and events.
## This will be REMOVED in Section 8.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F2:
			GameState.show_debug_text = not GameState.show_debug_text
			debug_label.visible = GameState.show_debug_text
			get_viewport().set_input_as_handled()
		if event.keycode == KEY_F3:
			print("DEBUG: F3 pressed — skipping to next Sol.")
			_advance_sol()
			get_viewport().set_input_as_handled()


# ==================== Sol clock ====================

func _advance_sol() -> void:
	_current_sol += 1

	# Step 1: Notify farms and other listeners that a new Sol started.
	EventBus.day_changed.emit(_current_sol)

	# Step 2: Process building power budget.
	# WHY: buildings run BEFORE the event director ticks, so the shield
	#       produced this Sol is available if a radiation check fires.
	_process_buildings()

	# Step 3: Let the event director tick (may finish or start an event).
	# WHY: called AFTER buildings so the player can prepare for events
	#       during the warning Sol.
	event_director.on_sol_completed(_current_sol)

	_refresh_label()
	_check_mission_end()


func _process_buildings() -> void:
	var buildings: Array = get_tree().get_nodes_in_group("buildings")
	var active_event: Dictionary = event_director.get_active_event()
	_power_produced = 0
	_power_needed = 0

	# WHY: oxygen leak drains oxygen BEFORE building processing,
	#       so the player feels the pressure of the leak immediately.
	_apply_oxygen_leak(active_event)

	# --- Step 1: PRODUCERS add their outputs first ---
	# This puts energy into the pool BEFORE consumers try to spend it.
	for b: Node in buildings:
		if not b.is_on():
			continue
		if b.get_power_per_sol() > 0:
			var power_amount: int = b.get_power_per_sol()
			# WHY: during a dust storm, only the affected building type
			#       has its output reduced. The multiplier comes from JSON.
			if (
				str(active_event.get("type", "")) == "dust_storm"
				and str(active_event.get("affected_building_id", "")) == b.building_id
			):
				power_amount = roundi(
					float(power_amount)
					* float(active_event.get("power_output_multiplier", 1.0))
				)
			_power_produced += power_amount
			var produces: Dictionary = b.get_produces()
			for res_type: String in produces:
				var amount: int = int(produces[res_type])
				if res_type == "energy":
					# WHY: energy uses the modified power_amount (after dust storm).
					amount = power_amount
				ResourceManager.add(res_type, amount)

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
			EventBus.notice.emit("%s SHUT DOWN — NO POWER" % b.building_id.to_upper())

	# --- Step 3: Shield decay ---
	# WHY: shield decays each Sol whether the generator is ON or OFF.
	#       This means the player must KEEP the generator powered — turning
	#       it on once and then off doesn't give permanent protection.
	#       GAMEPLAY APPROXIMATION: real shield degradation depends on
	#       habitat design, materials, and radiation environment.
	for b: Node in buildings:
		# WHY: no is_on() check — shield decays regardless of power state.
		if b.get_shield_decay_per_sol() > 0:
			var decay: int = b.get_shield_decay_per_sol()
			var current_shield: int = ResourceManager.get_amount("shield")
			var actual_decay: int = mini(decay, current_shield)
			if actual_decay > 0:
				ResourceManager.spend({"shield": actual_decay})

	print("Sol %d complete — produced %d / needed %d" % [
		_current_sol, _power_produced, _power_needed
	])


# ==================== Event effect application ====================

## WHY: oxygen leak removes oxygen each Sol the event is active.
##       The loss is capped at current oxygen so it never goes negative.
func _apply_oxygen_leak(active_event: Dictionary) -> void:
	if str(active_event.get("type", "")) != "oxygen_leak":
		return
	var leak_amount: int = maxi(0, int(active_event.get("oxygen_loss_per_sol", 0)))
	var oxygen_available: int = ResourceManager.get_amount("oxygen")
	var actual_loss: int = mini(leak_amount, oxygen_available)
	if actual_loss > 0:
		ResourceManager.spend({"oxygen": actual_loss})
		print("  → Oxygen leak: lost %d (had %d)" % [actual_loss, oxygen_available])


## WHY: radiation check happens when the event FINISHES, not when it starts.
##       This gives the player the entire warning Sol to prepare (power the
##       shield generator, boost shield).
##       GAMEPLAY APPROXIMATION: the shield check is a simplified game
##       mechanic — real radiation protection involves habitat design,
##       regolith shielding, and mission planning.  The shield_needed and
##       oxygen_penalty values come from event data files (events.json or
##       event_thresholds.json), NOT from NASA dose-rate measurements.
func _apply_radiation_check(event_data: Dictionary) -> void:
	if str(event_data.get("type", "")) != "radiation_warning":
		return

	var shield_needed: int = int(event_data.get("shield_needed", 0))
	var oxygen_penalty: int = int(event_data.get("oxygen_penalty", 0))

	# WHY: if thresholds are zero the data file is misconfigured.
	#       Warn but don't crash — just skip the check.
	if shield_needed <= 0 and oxygen_penalty <= 0:
		push_warning("Radiation event '%s' has no shield_needed or oxygen_penalty — skipping check." % str(event_data.get("id", "?")))
		return

	var shield_now: int = ResourceManager.get_amount("shield")

	if shield_now >= shield_needed:
		# Protected: shield absorbs the radiation.
		ResourceManager.spend({"shield": shield_needed})
		print("  → Shield absorbed radiation (-%d shield)" % shield_needed)
		_latest_event_notice = "Shield held! Lost %d shield points." % shield_needed
		EventBus.notice.emit("SHIELD HELD — LOST %d SHIELD" % shield_needed)
	else:
		# Exposed: crew must shelter, which costs oxygen.
		var current_o2: int = ResourceManager.get_amount("oxygen")
		var actual_penalty: int = mini(oxygen_penalty, current_o2)
		if actual_penalty > 0:
			ResourceManager.spend({"oxygen": actual_penalty})
		print("  → RADIATION EXPOSURE! Shield too low (%d < %d). Lost %d oxygen." % [
			shield_now, shield_needed, actual_penalty
		])
		_latest_event_notice = "Radiation exposure! Shield too low — lost %d oxygen!" % actual_penalty
		EventBus.notice.emit("RADIATION EXPOSURE — LOST %d OXYGEN" % actual_penalty)
	_refresh_event_label()


# ==================== Signal callbacks ====================

func _on_resource_changed(_type: String, _new_total: int) -> void:
	_refresh_label()
	if _type == "oxygen":
		# Below a quarter tank the suit starts recycling air audibly.
		AudioManager.set_oxygen_critical(_new_total > 0 and _new_total <= 25)


func _on_event_started(event: Dictionary) -> void:
	# WHY: store the full event data so we can apply effects on finish.
	_current_event_data = event.duplicate(true)

	# WHY: all events (NASA and non-NASA) emit game_event_started
	#       so any listener (HUD, analytics) gets notified.
	#       NOTE: game_event_started is an ADDITION to the original
	#       shared contract (added during first events integration).
	EventBus.game_event_started.emit(event)

	# WHY: NASA events display their briefing via _on_space_weather_warning
	#       (triggered by the director's EventBus.space_weather_warning emission).
	#       Non-NASA events display here.
	if bool(event.get("archived_nasa_data", false)):
		print("EVENT STARTED (NASA): '%s'" % event.get("title", "?"))
		return
	_show_event_briefing(event)
	print("EVENT STARTED: '%s'" % event.get("title", "?"))


func _on_space_weather_warning(event: Dictionary) -> void:
	_show_event_briefing(event)
	print("EventBus.space_weather_warning → %s" % event.get("title", "?"))


## WHY: shows the event text and, for NASA events, the real archived
##       measurements so kids learn the real science.
##       IMPORTANT: the RadLab readings are absorbed dose rates, not
##       crew health impacts.  The briefing presents them as measurements
##       and does NOT claim a direct link to in-game damage.
func _show_event_briefing(event: Dictionary) -> void:
	_showing_event_briefing = true
	_latest_event_notice = "%s\n%s" % [
		str(event.get("title", "Event")),
		str(event.get("lesson", ""))
	]
	if bool(event.get("archived_nasa_data", false)):
		var measured_records: Variant = event.get("radiation_records", [])
		if measured_records is Array:
			for record: Variant in measured_records:
				if not record is Dictionary:
					continue
				# WHY: show the real measurement and its unit exactly as
				#       recorded.  "absorbed dose rate" is what the instrument
				#       measured — it is NOT a crew health damage number.
				_latest_event_notice += "\nCuriosity measured %s: %.2f %s" % [
					str(record.get("date", "")),
					float(record.get("daily_mean_absorbed_dose_rate", 0.0)),
					str(record.get("unit", ""))
				]
		_latest_event_notice += "\n(These are real measurements, not health limits.)"
		_latest_event_notice += "\nNASA source: %s" % str(event.get("source", "NASA"))
		_latest_event_notice += "\nPower the Shield Generator before the next Sol to protect the crew."
	_refresh_event_label()


func _on_event_finished(result: Dictionary) -> void:
	var event_id: String = str(result.get("event_id", "unknown"))
	print("Event finished: %s" % event_id)

	# WHY: apply the radiation check using the stored event data.
	#       The director already cleared its _active_event, so we use
	#       _current_event_data which was saved in _on_event_started.
	if not _current_event_data.is_empty():
		_apply_radiation_check(_current_event_data)
		_current_event_data = {}

	_latest_event_notice = "No event."
	_showing_event_briefing = false
	_refresh_event_label()
	# NOTE: game_event_ended is an ADDITION to the original shared
	#       contract (added during first events integration).
	EventBus.game_event_ended.emit(event_id)


func _on_space_weather_resolved(result: Dictionary) -> void:
	print("EventBus.space_weather_resolved → %s" % str(result))


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


func _refresh_event_label() -> void:
	if is_instance_valid(event_label):
		event_label.text = "EVENT BRIEFING\n" + _latest_event_notice
	if is_instance_valid(event_panel):
		# The painted SPACE WEATHER panel now shows the same briefing.
		event_panel.visible = _showing_event_briefing and not _has_pack_ui()


# ==================== Pack v2 interface ====================
# Read-only accessors, so the painted HUD and panels never poke private state.

func get_current_sol() -> int:
	return _current_sol


func get_power_stats() -> Dictionary:
	return {
		"produced": _power_produced,
		"needed": _power_needed,
		"sol": _current_sol,
		"target": int(GameState.target_sols),
	}


func _has_pack_ui() -> bool:
	return get_node_or_null("HudLayer") != null


## Mission end rules: survive the target number of Sols, or run out of oxygen.
## WHY checked after the Sol completes: the player gets the whole Sol to recover.
func _check_mission_end() -> void:
	if not GameState.mission_running:
		return
	if ResourceManager.get_amount("oxygen") <= 0:
		GameState.end_mission("failed", "OXYGEN DEPLETED")
		EventBus.mission_over.emit("failed", "OXYGEN DEPLETED")
		return
	if _current_sol >= int(GameState.target_sols):
		GameState.end_mission("complete", "")
		EventBus.mission_over.emit("complete", "")
