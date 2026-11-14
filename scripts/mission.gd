## scripts/mission.gd
## Autoload "Mission": the running rules of one AstroBase-Commander run.
##
## Everything here is driven by the JSON pack in res://data/:
##   systems.json        -> what each base system produces and costs every Sol
##   resources.json      -> daily consumption, caps, critical stores
##   events.json         -> random / scripted events, their effects and choices
##   nasa/*.json         -> the historical September 2017 record (scripted, not live)
##   scenarios/          -> start Sol, overrides, scripted schedules, objectives
##   mission_progression -> phases and milestone rewards
##   achievements.json   -> unlock rules and rewards
##   ending_rules.json   -> loss conditions, story endings and scoring
##   story/campaign_30_sols.json -> the 30-day story (cards, choices, consequences)
##
## End of every Sol (see process_end_of_sol):
##   1 systems in processing_order pay their energy (and water) cost, then produce
##   2 daily consumption x difficulty x consumption modifiers
##   3 per-Sol modifiers, morale effects, habitat recovery, caps
##   4 loss check -> Mission Paused
##   5 history, milestones, achievements, objectives
##   6 modifiers and events tick down
##   7 end of the run, or the 0.35 random-event roll and the next Sol's cards
extends Node

signal cards_ready
signal sol_started(sol: int)
signal sol_processed(report: Dictionary)
signal state_changed
signal run_finished(ending: Dictionary)

const SUPPLY: Array[String] = ["energy", "water", "food", "oxygen"]
const LIFE_SUPPORT: Array[String] = ["oxygen_generator", "water_recycler", "greenhouse"]
const CRITICAL_SYSTEMS: Array[String] = ["solar_panel", "oxygen_generator", "water_recycler", "habitat"]
## World buildings that share one system entry: the starting base has two solar panels,
## so each delivers half of the 18-energy array. Extra panels the player builds add more.
const STOCK_COUNT: Dictionary = {"solar_panel": 2}
const SYSTEM_PROPERTIES: Array[String] = ["production_multiplier", "energy_cost_multiplier", "water_cost_multiplier"]
const RESOURCE_PROPERTIES: Array[String] = ["consumption_multiplier", "capacity_multiplier"]
const EVENT_CATEGORY_SCORE: Dictionary = {
	"life_support": "safety", "space_weather": "safety", "power": "resources",
	"food": "resources", "habitat": "infrastructure", "maintenance": "infrastructure",
	"environmental": "infrastructure", "communications": "science",
}
const AUDIO_TYPE: Dictionary = {
	"dust_storm": "dust_storm", "dust_devil": "dust_storm",
	"oxygen_leak": "oxygen_leak", "radiation_burst": "radiation_warning",
}

var running: bool = false
var ended: bool = false
var sol: int = 1
var ending: Dictionary = {}
var evaluation: Dictionary = {}

var story: Dictionary = {}
var story_days: Dictionary = {}       # int -> day dictionary
var modifiers: Array = []
var flags: Dictionary = {}
var counters: Dictionary = {}
var decisions: Array = []
var score_points: Dictionary = {}
var history: Array = []
var shortage_sols: int = 0
var faults: Array = []
var active_events: Array = []
var events_survived: Dictionary = {}
var random_weeks_used: Dictionary = {}
var achievements_unlocked: Array = []
var milestones_done: Array = []
var objectives: Array = []            # [{id, description, condition, kind, done, failed}]
var card_queue: Array = []
var last_report: Dictionary = {}
var completed_sols: int = 0

var _systems: Dictionary = {}
var _order: Array = []
var _building_to_system: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _world_attached: bool = false


func _ready() -> void:
	_load_systems()


func _load_systems() -> void:
	_systems.clear()
	_building_to_system.clear()
	for row: Variant in DataLoader.get_systems():
		if row is Dictionary:
			var id: String = str(row.get("id", ""))
			_systems[id] = row
			var bid: String = str(row.get("building_id", ""))
			if not bid.is_empty():
				_building_to_system[bid] = id
	var order: Variant = DataLoader.get_systems_data().get("processing_order", [])
	_order = order if order is Array and not (order as Array).is_empty() else _systems.keys()


# ================================================================== run lifecycle

## GameState.begin_mission() calls this; the world is attached later by main.
func begin_run() -> void:
	running = true
	ended = false
	ending = {}
	evaluation = {}
	sol = GameState.get_start_sol()
	completed_sols = sol - 1
	modifiers.clear()
	flags.clear()
	counters.clear()
	decisions.clear()
	score_points = {"resources": 0, "safety": 0, "wellbeing": 0, "science": 0, "infrastructure": 0}
	history.clear()
	shortage_sols = 0
	faults.clear()
	active_events.clear()
	events_survived.clear()
	random_weeks_used.clear()
	achievements_unlocked.clear()
	milestones_done.clear()
	card_queue.clear()
	last_report = {}
	_world_attached = false
	_rng.randomize()
	story = {}
	story_days.clear()
	var scenario: Dictionary = GameState.get_scenario()
	if GameState.is_story_campaign():
		story = DataLoader.get_story(_story_path(scenario))
		for day: Variant in story.get("days", []):
			if day is Dictionary:
				story_days[int(day.get("day", 0))] = day
	_build_objectives(scenario)


func _story_path(scenario: Dictionary) -> String:
	var ref: String = str(scenario.get("story_ref", "story/campaign_30_sols.json"))
	return "res://data/%s" % ref


## main.gd calls this once the buildings exist: start states, then the first Sol.
func attach_world() -> void:
	if not running:
		begin_run()
	_world_attached = true
	var off: Array = []
	if GameState.is_story_campaign():
		var start_state: Variant = story.get("campaign_start_state", {})
		if start_state is Dictionary:
			off = (start_state as Dictionary).get("disabled_systems", [])
	else:
		var enabled: Variant = GameState.get_scenario().get("enabled_system_ids", [])
		for sys_id: String in _systems:
			if enabled is Array and not (enabled as Array).has(sys_id):
				off.append(sys_id)
	for sys_id: Variant in off:
		for b: Node in _buildings_for(str(sys_id)):
			b.set_on(false)
	_start_sol(sol)


func is_world_attached() -> bool:
	return _world_attached


# ================================================================== queries

func get_system_def(system_id: String) -> Dictionary:
	return _systems.get(system_id, {})


func get_system_ids() -> Array:
	return _order.duplicate()


func system_for_building(building_id: String) -> String:
	return str(_building_to_system.get(building_id, ""))


## What ONE building of this type adds per Sol (systems.json, split across the stock
## array, solar scaled by the landing site). {energy_cost, water_cost, produces{}, effect}
func building_numbers(building_id: String) -> Dictionary:
	var system_id: String = system_for_building(building_id)
	var sys: Dictionary = get_system_def(system_id)
	var out: Dictionary = {"system": system_id, "energy_cost": 0, "water_cost": 0, "produces": {}, "effect": ""}
	if sys.is_empty():
		return out
	var share: float = 1.0 / float(STOCK_COUNT.get(system_id, 1))
	out["energy_cost"] = roundi(float(sys.get("energy_cost", 0)) * share)
	out["water_cost"] = roundi(float(sys.get("water_cost", 0)) * share)
	var produces: Variant = sys.get("produces", {})
	if produces is Dictionary:
		for res: String in produces:
			var m: float = share
			if system_id == "solar_panel":
				m *= GameState.get_site_modifier("solar_output", 1.0)
			out["produces"][ResourceManager.canonical(res)] = roundi(float(produces[res]) * m)
	if system_id == "radiation_shield":
		out["produces"]["shield"] = int(sys.get("recharge_per_sol", 0))
	if system_id == "habitat":
		out["produces"]["crew_health"] = int(sys.get("crew_health_recovery_per_sol", 0))
	out["effect"] = str(sys.get("effect", "")).replace("_", " ")
	return out


func _buildings_for(system_id: String) -> Array:
	var bid: String = str(get_system_def(system_id).get("building_id", system_id))
	var result: Array = []
	if not is_inside_tree():
		return result
	for b: Node in get_tree().get_nodes_in_group("buildings"):
		if str(b.get("building_id")) == bid:
			result.append(b)
	return result


func is_system_locked(system_id: String) -> bool:
	return not get_lock_reason(system_id).is_empty()


func get_lock_reason(system_id: String) -> String:
	for m: Dictionary in modifiers:
		if m["kind"] == "lock" and m["target"] == system_id:
			return str(m.get("label", m["tag"]))
	return ""


## Enabled = at least one of its buildings is ON and no lock holds it down.
func is_system_enabled(system_id: String) -> bool:
	if is_system_locked(system_id):
		return false
	for b: Node in _buildings_for(system_id):
		if b.is_on():
			return true
	return false


func get_multiplier(target: String, property: String) -> float:
	var value: float = 1.0
	for m: Dictionary in modifiers:
		if m["kind"] != "mult" or m["property"] != property:
			continue
		if m["target"] == target or (m["target"] == "all_systems" and _systems.has(target)):
			value *= float(m["value"])
	return value


func has_flag(flag: String) -> bool:
	return flags.has(flag)


func set_flag(flag: String) -> void:
	if flags.has(flag):
		return
	flags[flag] = true
	_update_objectives(false)
	state_changed.emit()


func get_counter(id: String) -> int:
	return int(counters.get(id, 0))


func get_story_day(day: int) -> Dictionary:
	return story_days.get(day, {})


func get_phase() -> Dictionary:
	for p: Variant in DataLoader.get_mission_progression().get("phases", []):
		if p is Dictionary and sol >= int(p.get("sol_start", 0)) and sol <= int(p.get("sol_end", 0)):
			return p
	return {}


func get_week() -> Dictionary:
	for w: Variant in story.get("weeks", []):
		if w is Dictionary and sol >= int(w.get("sol_start", 0)) and sol <= int(w.get("sol_end", 0)):
			return w
	return {}


func get_science_target() -> int:
	var ev: Variant = story.get("evaluation", {})
	if ev is Dictionary:
		return int((ev as Dictionary).get("science_target", 60))
	return 60


## Short labels for the HUD: what is changing the base right now.
func get_active_labels() -> Array:
	var out: Array = []
	for e: Dictionary in active_events:
		out.append("%s (%d SOL)" % [str(e["def"].get("name", e["id"])).to_upper(), int(e["remaining"])])
	for m: Dictionary in modifiers:
		if m.get("event", false):
			continue
		var label: String = str(m.get("label", ""))
		if label.is_empty() or out.has(label):
			continue
		out.append(label)
	return out


func get_objective_lines() -> Array:
	var lines: Array = []
	if GameState.is_story_campaign():
		var phase: Dictionary = get_phase()
		if not phase.is_empty():
			lines.append({"text": str(phase.get("focus", "")), "state": "info"})
		lines.append({"text": "Science %d / %d target" % [ResourceManager.get_amount("science"), get_science_target()],
			"state": "done" if ResourceManager.get_amount("science") >= get_science_target() else "open"})
		return lines
	for o: Dictionary in objectives:
		var state: String = "failed" if o["failed"] else ("done" if o["done"] else "open")
		lines.append({"text": str(o["description"]), "state": state})
	return lines


# ================================================================== Sol start

func _start_sol(number: int) -> void:
	sol = number
	EventBus.day_changed.emit(sol)
	sol_started.emit(sol)
	if GameState.is_story_campaign():
		var day: Dictionary = get_story_day(sol)
		if not day.is_empty():
			_start_story_day(day)
	else:
		var schedule: Variant = GameState.get_scenario().get("scripted_event_schedule", {})
		if schedule is Dictionary and (schedule as Dictionary).has(str(sol)):
			var event_id: String = str(schedule[str(sol)])
			var ref: String = ""
			if event_id == "radiation_burst":
				ref = str(GameState.get_scenario().get("historical_data_ref", ""))
			var inst: Dictionary = start_event(event_id, ref, true)
			if not inst.is_empty():
				_queue({"kind": "event", "event": inst})
	_update_objectives(false)
	state_changed.emit()
	if not card_queue.is_empty():
		cards_ready.emit()


func _start_story_day(day: Dictionary) -> void:
	var inst: Dictionary = {}
	var event_id: String = str(day.get("event_id", ""))
	if not event_id.is_empty():
		inst = start_event(event_id, str(day.get("historical_ref", "")), true)
	var ctx: Dictionary = {"tag": "day%d" % sol, "duration": 1, "scale": GameState.get_resource_multiplier(), "day": day}
	apply_effects(_array(day.get("start_effects", [])), ctx)
	_queue({"kind": "story", "day": day, "event": inst})


func _queue(card: Dictionary) -> void:
	card_queue.append(card)


func has_cards() -> bool:
	return not card_queue.is_empty()


func pop_card() -> Dictionary:
	if card_queue.is_empty():
		return {}
	return card_queue.pop_front()


# ================================================================== events

## Starts an event from events.json. Base effects apply now, tagged with the event id.
func start_event(event_id: String, historical_ref: String = "", started_at_sol_start: bool = false) -> Dictionary:
	var def: Dictionary = DataLoader.get_event(event_id)
	if def.is_empty():
		push_warning("Mission: unknown event '%s'" % event_id)
		return {}
	var duration: int = maxi(1, int(def.get("duration_sols", 1)))
	var inst: Dictionary = {
		"id": event_id, "def": def, "remaining": duration, "historical_ref": historical_ref,
		"resolved": false, "started_sol": sol if started_at_sol_start else sol + 1,
	}
	active_events.append(inst)
	var ctx: Dictionary = {"tag": event_id, "duration": duration, "scale": GameState.get_resource_multiplier(),
		"event": true, "label": str(def.get("name", event_id)).to_upper()}
	apply_effects(_array(def.get("effects", [])), ctx)
	var audio: Dictionary = def.duplicate(true)
	audio["type"] = AUDIO_TYPE.get(event_id, event_id)
	audio["title"] = str(def.get("name", event_id))
	audio["historical_ref"] = historical_ref
	EventBus.game_event_started.emit(audio)
	EventBus.notice.emit("%s" % str(def.get("name", event_id)).to_upper())
	state_changed.emit()
	return inst


func _event_choice_def(def: Dictionary, choice_id: String) -> Dictionary:
	for ch: Variant in def.get("player_choices", []):
		if ch is Dictionary and str(ch.get("id", "")) == choice_id:
			return ch
	return {}


func is_radiation_event(def: Dictionary) -> bool:
	return def.has("effects_if_unprotected")


## Requirements to raise the shield (historical record raises the shield needed to 15).
func radiation_requirements(inst: Dictionary) -> Dictionary:
	var def: Dictionary = inst.get("def", {})
	var req: Dictionary = def.get("requirements", {})
	var shield: int = int(req.get("shield", 10))
	var ref: String = str(inst.get("historical_ref", ""))
	if not ref.is_empty():
		shield = maxi(shield, int(DataLoader.get_threshold_for(ref).get("shield_required", shield)))
	return {"system": str(req.get("system_enabled", "radiation_shield")), "energy": int(req.get("energy", 10)), "shield": shield}


func radiation_penalty(inst: Dictionary) -> int:
	var def: Dictionary = inst.get("def", {})
	var penalty: int = 15
	for e: Variant in def.get("effects_if_unprotected", []):
		if e is Dictionary and str(e.get("target", "")) == "crew_health":
			penalty = int(e.get("value", penalty))
	var ref: String = str(inst.get("historical_ref", ""))
	if not ref.is_empty():
		penalty = int(DataLoader.get_threshold_for(ref).get("crew_health_penalty_if_unprotected", penalty))
	return penalty


## Applies one event choice (cost already paid by the caller).
func _resolve_event(inst: Dictionary, choice_id: String, resolution: String) -> void:
	var def: Dictionary = inst.get("def", {})
	var event_id: String = str(def.get("id", ""))
	var remaining: int = int(inst.get("remaining", def.get("duration_sols", 1)))
	var ctx: Dictionary = {"tag": event_id, "duration": maxi(1, remaining), "scale": 1.0, "event": true,
		"label": str(def.get("name", event_id)).to_upper()}
	if is_radiation_event(def):
		flags["radiation_response_selected"] = true
		if resolution == "unprotected" or choice_id.is_empty():
			var penalty: int = roundi(float(radiation_penalty(inst)) * GameState.get_resource_multiplier())
			ResourceManager.apply_delta("crew_health", -penalty)
			flags["radiation_unprotected"] = true
		elif choice_id == "activate_shield" or resolution == "protected":
			counters["radiation_event_protected"] = get_counter("radiation_event_protected") + 1
			flags["radiation_protected"] = true
		else:
			apply_effects(_array(_event_choice_def(def, choice_id).get("effects", [])), ctx)
			counters["radiation_event_protected"] = get_counter("radiation_event_protected") + 1
			flags["radiation_sheltered"] = true
	else:
		var ch: Dictionary = _event_choice_def(def, choice_id)
		var effects: Array = _array(ch.get("effects", []))
		apply_effects(effects, ctx)
		for e: Variant in effects:
			if e is Dictionary and str(e.get("property", "")) == "enabled" and bool(e.get("value", false)) \
					and LIFE_SUPPORT.has(str(e.get("target", ""))):
				counters["life_support_system_repaired"] = get_counter("life_support_system_repaired") + 1
				break
	inst["resolved"] = true


func choice_cost(choice: Dictionary, event_def: Dictionary) -> Dictionary:
	var cost: Variant = choice.get("cost", null)
	if cost is Dictionary:
		return cost
	var ev_choice: String = str(choice.get("event_choice", ""))
	if not ev_choice.is_empty():
		var c: Variant = _event_choice_def(event_def, ev_choice).get("cost", {})
		if c is Dictionary:
			return c
	return {}


## "" when the choice can be taken, otherwise why not (shown on the button).
func choice_block_reason(card: Dictionary, choice: Dictionary) -> String:
	var inst: Dictionary = card.get("event", {})
	var def: Dictionary = _event_def_for_choice(card, choice)
	var cost: Dictionary = choice_cost(choice, def)
	for key: String in cost:
		if ResourceManager.get_amount(key) < int(cost[key]):
			return "NEEDS %d %s" % [int(cost[key]), ResourceManager.get_display_name(key).to_upper()]
	var wants_protection: bool = str(choice.get("event_resolution", "")) == "protected" \
		or (card.get("kind", "") == "event" and str(choice.get("id", "")) == "activate_shield")
	if wants_protection and not inst.is_empty() and is_radiation_event(inst.get("def", {})):
		var req: Dictionary = radiation_requirements(inst)
		if not is_system_enabled(str(req["system"])):
			return "SHIELD GENERATOR IS OFF"
		if ResourceManager.get_amount("energy") < int(req["energy"]):
			return "NEEDS %d ENERGY" % int(req["energy"])
		if ResourceManager.get_amount("shield") < int(req["shield"]):
			return "NEEDS %d SHIELD" % int(req["shield"])
	return ""


func _event_def_for_choice(card: Dictionary, choice: Dictionary) -> Dictionary:
	var override: String = str(choice.get("event_id", ""))
	if not override.is_empty():
		return DataLoader.get_event(override)
	var inst: Dictionary = card.get("event", {})
	return inst.get("def", {})


## A story card choice. Returns {consequence, changes, insight, source}.
func choose_story(card: Dictionary, choice: Dictionary) -> Dictionary:
	var day: Dictionary = card.get("day", {})
	var inst: Dictionary = card.get("event", {})
	var before: Dictionary = ResourceManager.get_all()
	var def: Dictionary = _event_def_for_choice(card, choice)
	ResourceManager.spend(choice_cost(choice, def))
	var ev_choice: String = str(choice.get("event_choice", ""))
	var resolution: String = str(choice.get("event_resolution", ""))
	if not ev_choice.is_empty() or not resolution.is_empty():
		var target: Dictionary = inst
		if not str(choice.get("event_id", "")).is_empty() and str(inst.get("id", "")) != str(choice["event_id"]):
			target = {"id": str(choice["event_id"]), "def": def, "remaining": 1, "historical_ref": ""}
		if not target.is_empty():
			_resolve_event(target, ev_choice, resolution)
	var ctx: Dictionary = {"tag": "day%d_%s" % [int(day.get("day", sol)), str(choice.get("id", ""))],
		"duration": -1, "scale": 1.0, "day": day}
	apply_effects(_array(choice.get("effects", [])), ctx)
	apply_effects(_array(choice.get("extra_effects", [])), ctx)
	var counter_add: Variant = choice.get("counters", {})
	if counter_add is Dictionary:
		for key: String in counter_add:
			counters[key] = get_counter(key) + int(counter_add[key])
	for flag: Variant in choice.get("flags", []):
		flags[str(flag)] = true
	var scores: Variant = choice.get("scores", {})
	if scores is Dictionary:
		for key: String in scores:
			score_points[key] = int(score_points.get(key, 0)) + int(scores[key])
	var consequence: String = format_text(str(choice.get("consequence", "")))
	decisions.append({"sol": sol, "title": str(day.get("title", "")), "label": str(choice.get("label", "")),
		"consequence": consequence, "scores": scores if scores is Dictionary else {}, "kind": "story"})
	var insight: Dictionary = day.get("insight", {})
	return _after_choice(before, consequence, insight)


## A random or scripted event card choice ("" = no affordable response).
func choose_event(card: Dictionary, choice_id: String) -> Dictionary:
	var inst: Dictionary = card.get("event", {})
	var def: Dictionary = inst.get("def", {})
	var before: Dictionary = ResourceManager.get_all()
	var choice: Dictionary = _event_choice_def(def, choice_id)
	var cost: Dictionary = choice.get("cost", {}) if choice.get("cost", {}) is Dictionary else {}
	ResourceManager.spend(cost)
	_resolve_event(inst, choice_id, "" if not choice_id.is_empty() else "unprotected")
	var category: String = str(EVENT_CATEGORY_SCORE.get(str(def.get("category", "")), "resources"))
	var delta: int = 2 if not cost.is_empty() else -1
	if choice_id.is_empty():
		delta = -2
	score_points[category] = int(score_points.get(category, 0)) + delta
	var label: String = str(choice.get("label", "No response possible"))
	var consequence: String = "Response: %s." % label
	decisions.append({"sol": sol, "title": str(def.get("name", "")), "label": label,
		"consequence": consequence, "scores": {category: delta}, "kind": "event"})
	var source: Dictionary = def.get("source", {})
	var insight: Dictionary = {"text": str(def.get("lesson", "")), "url": str(source.get("url", "")),
		"title": "%s · %s" % [str(source.get("organization", "")), str(source.get("title", ""))]}
	return _after_choice(before, consequence, insight)


func _after_choice(before: Dictionary, consequence: String, insight: Dictionary) -> Dictionary:
	var changes: String = _diff_text(before, ResourceManager.get_all())
	_check_achievements()
	_update_objectives(false)
	state_changed.emit()
	var result: Dictionary = {"consequence": consequence, "changes": changes,
		"insight": str(insight.get("text", "")), "source": _source_line(insight)}
	var reason: String = _loss_reason()
	if not reason.is_empty():
		_finish(false, reason)
	return result


func _source_line(insight: Dictionary) -> String:
	if insight.has("title"):
		return "%s  %s" % [str(insight.get("title", "")), str(insight.get("url", ""))]
	var source_id: String = str(insight.get("source_id", ""))
	if source_id.is_empty():
		return "Game lesson (gameplay rule, not NASA data)"
	var src: Dictionary = DataLoader.get_data_source(source_id)
	if src.is_empty():
		return source_id
	return "%s · %s  %s" % [str(src.get("organization", "")), str(src.get("title", "")), str(src.get("url", ""))]


# ================================================================== effects

func _array(value: Variant) -> Array:
	return value if value is Array else []


func condition_ok(d: Dictionary) -> bool:
	if d.has("if_flag") and not has_flag(str(d["if_flag"])):
		return false
	if d.has("unless_flag") and has_flag(str(d["unless_flag"])):
		return false
	if d.has("if_system_enabled") and not is_system_enabled(str(d["if_system_enabled"])):
		return false
	if d.has("unless_system_enabled") and is_system_enabled(str(d["unless_system_enabled"])):
		return false
	return true


## ctx: tag, duration (-1 permanent), scale (damage multiplier for subtracts), event, label, day
func apply_effects(effects: Array, ctx: Dictionary) -> void:
	for raw: Variant in effects:
		if not raw is Dictionary:
			continue
		var e: Dictionary = raw
		if not condition_ok(e):
			continue
		if e.has("include"):
			var day: Dictionary = ctx.get("day", {})
			apply_effects(_array(day.get(str(e["include"]), [])), ctx)
			continue
		if e.has("remove_modifier"):
			remove_modifier(str(e["remove_modifier"]))
			continue
		var op: String = str(e.get("operation", ""))
		var prop: String = str(e.get("property", ""))
		var target: String = str(e.get("target", ""))
		var value: Variant = e.get("value", 0)
		var tag: String = str(e.get("tag", ctx.get("tag", "effect")))
		match op:
			"add":
				ResourceManager.apply_delta(target, int(value))
				continue
			"subtract":
				ResourceManager.apply_delta(target, -roundi(float(value) * float(ctx.get("scale", 1.0))))
				continue
			"add_per_sol", "subtract_per_sol":
				var amount: int = int(value)
				if op == "subtract_per_sol":
					amount = -roundi(float(value) * float(ctx.get("scale", 1.0)))
				_add_modifier({"kind": "per_sol", "target": target, "property": "", "value": amount, "tag": tag,
					"remaining": _duration(e, ctx), "event": ctx.get("event", false),
					"label": "%s %+d/SOL" % [ResourceManager.get_display_name(target).to_upper(), amount]})
				continue
			"redistribute":
				_redistribute(int(value))
				continue
			"boost_lowest":
				var low: String = lowest_supply()
				ResourceManager.apply_delta(low, int(value))
				continue
		if prop == "dust":
			for b: Node in _buildings_for("solar_panel"):
				b.set_dusty(bool(value))
		elif prop == "enabled":
			_set_enabled(target, bool(value), e, ctx, tag)
		elif SYSTEM_PROPERTIES.has(prop) or RESOURCE_PROPERTIES.has(prop):
			_remove_matching(target, prop, tag)
			if not is_equal_approx(float(value), 1.0):
				var label: String = str(ctx.get("label", ""))
				if label.is_empty():
					label = _modifier_label(target, prop, float(value))
				_add_modifier({"kind": "mult", "target": target, "property": prop, "value": float(value),
					"tag": tag, "remaining": _duration(e, ctx), "event": ctx.get("event", false), "label": label})
			if prop == "capacity_multiplier":
				ResourceManager.set_capacity_multiplier(target, get_multiplier(target, prop))
	state_changed.emit()


func _duration(e: Dictionary, ctx: Dictionary) -> int:
	if bool(e.get("permanent", false)):
		return -1
	if e.has("duration_sols"):
		return maxi(1, int(e["duration_sols"]))
	return int(ctx.get("duration", -1))


func _modifier_label(target: String, prop: String, value: float) -> String:
	var name: String = target.replace("_", " ").to_upper()
	if _systems.has(target):
		name = str(_systems[target].get("name", name)).to_upper()
	elif ResourceManager.has_type(target):
		name = ResourceManager.get_display_name(target).to_upper()
	var what: String = {"production_multiplier": "OUTPUT", "energy_cost_multiplier": "POWER USE",
		"water_cost_multiplier": "WATER USE", "consumption_multiplier": "USE",
		"capacity_multiplier": "CAPACITY"}.get(prop, prop)
	return "%s %s x%.2f" % [name, what, value]


func _set_enabled(target: String, value: bool, e: Dictionary, ctx: Dictionary, tag: String) -> void:
	var blds: Array = _buildings_for(target)
	if value:
		var restored: bool = false
		for i: int in range(modifiers.size() - 1, -1, -1):
			if modifiers[i]["kind"] == "lock" and modifiers[i]["target"] == target:
				modifiers.remove_at(i)
				restored = true
		for b: Node in blds:
			b.set_on(true)
		if restored or not blds.is_empty():
			EventBus.notice.emit("%s ONLINE" % str(get_system_def(target).get("name", target)).to_upper())
		return
	var was_on: bool = false
	for b: Node in blds:
		was_on = was_on or b.is_on()
	for m: Dictionary in modifiers:
		if m["kind"] == "lock" and m["target"] == target:
			was_on = was_on or bool(m.get("prev_on", false))
	_remove_matching(target, "enabled", tag)
	var label: String = str(ctx.get("label", ""))
	if label.is_empty():
		label = "%s OFFLINE" % str(get_system_def(target).get("name", target)).to_upper()
	_add_modifier({"kind": "lock", "target": target, "property": "enabled", "value": false, "tag": tag,
		"remaining": _duration(e, ctx), "prev_on": was_on, "event": ctx.get("event", false), "label": label})
	for b: Node in blds:
		b.set_on(false)


func _add_modifier(m: Dictionary) -> void:
	modifiers.append(m)


func _remove_matching(target: String, prop: String, tag: String) -> void:
	for i: int in range(modifiers.size() - 1, -1, -1):
		var m: Dictionary = modifiers[i]
		if m["target"] == target and m["property"] == prop and m["tag"] == tag:
			modifiers.remove_at(i)


func remove_modifier(tag: String) -> void:
	var touched_capacity: Array = []
	for i: int in range(modifiers.size() - 1, -1, -1):
		var m: Dictionary = modifiers[i]
		if m["tag"] == tag:
			modifiers.remove_at(i)
			if m["kind"] == "lock":
				_release_lock(m)
			if m["property"] == "capacity_multiplier":
				touched_capacity.append(m["target"])
	for res: Variant in touched_capacity:
		ResourceManager.set_capacity_multiplier(str(res), get_multiplier(str(res), "capacity_multiplier"))
	state_changed.emit()


func _release_lock(m: Dictionary) -> void:
	var target: String = str(m["target"])
	if is_system_locked(target):
		return
	if bool(m.get("prev_on", false)):
		for b: Node in _buildings_for(target):
			b.set_on(true)
		EventBus.notice.emit("%s BACK ONLINE" % str(get_system_def(target).get("name", target)).to_upper())


func _redistribute(amount: int) -> void:
	var high: String = ""
	var low: String = lowest_supply()
	var best: float = -1.0
	for id: String in SUPPLY:
		var r: float = ResourceManager.get_ratio(id)
		if r > best and id != low:
			best = r
			high = id
	if high.is_empty():
		return
	var moved: int = mini(amount, ResourceManager.get_amount(high))
	ResourceManager.apply_delta(high, -moved)
	ResourceManager.apply_delta(low, moved)


func lowest_supply() -> String:
	var low: String = "energy"
	var worst: float = 999.0
	for id: String in SUPPLY:
		var r: float = ResourceManager.get_ratio(id)
		if r < worst:
			worst = r
			low = id
	return low


# ================================================================== end of Sol

func process_end_of_sol() -> Dictionary:
	if ended or not running:
		return {}
	var rm: Node = ResourceManager
	var diff: float = GameState.get_resource_multiplier()
	var report: Dictionary = {"sol": sol, "produced": {}, "costs": {}, "stalled": [], "consumed": {}}
	var energy_before: int = rm.get_amount("energy")
	var morale: int = rm.get_amount("crew_morale")
	var habitat_ran: bool = false

	# 1 — systems
	for sys_id: Variant in _order:
		var id: String = str(sys_id)
		var sys: Dictionary = get_system_def(id)
		if sys.is_empty() or is_system_locked(id):
			continue
		var share: float = 1.0 / float(STOCK_COUNT.get(id, 1))
		for b: Node in _buildings_for(id):
			if not b.is_on():
				continue
			var ratio: float = float(b.get_output_ratio())
			var ecost: int = roundi(float(sys.get("energy_cost", 0)) * share * ratio * get_multiplier(id, "energy_cost_multiplier"))
			var wcost: int = roundi(float(sys.get("water_cost", 0)) * share * get_multiplier(id, "water_cost_multiplier"))
			if rm.get_amount("energy") < ecost or rm.get_amount("water") < wcost:
				b.set_stalled(true)
				(report["stalled"] as Array).append(id)
				_log_fault("Sol %d: %s could not run (not enough %s)." % [sol, str(sys.get("name", id)),
					"energy" if rm.get_amount("energy") < ecost else "water"])
				continue
			b.set_stalled(false)
			rm.apply_delta("energy", -ecost)
			rm.apply_delta("water", -wcost)
			_tally(report["costs"], "energy", ecost)
			_tally(report["costs"], "water", wcost)
			var produces: Variant = sys.get("produces", {})
			if produces is Dictionary:
				for res: String in produces:
					var m: float = share * ratio * get_multiplier(id, "production_multiplier")
					if id == "solar_panel":
						m *= GameState.get_site_modifier("solar_output", 1.0) * float(b.get_dust_multiplier())
					if id == "research_lab" and morale < 40:
						m *= 0.5
					var amount: int = roundi(float(produces[res]) * m)
					rm.apply_delta(res, amount)
					_tally(report["produced"], rm.canonical(res), amount)
			if id == "radiation_shield":
				var recharge: int = int(sys.get("recharge_per_sol", 0))
				rm.apply_delta("shield", recharge)
				_tally(report["produced"], "shield", recharge)
			if id == "habitat":
				habitat_ran = true

	# 2 — daily consumption
	for res_id: Variant in rm.get_ids():
		var cps: int = rm.get_consumption_per_sol(str(res_id))
		if cps <= 0:
			continue
		var used: int = roundi(float(cps) * diff * get_multiplier(str(res_id), "consumption_multiplier"))
		rm.apply_delta(str(res_id), -used)
		_tally(report["consumed"], str(res_id), used)

	# 3 — per-Sol modifiers, morale, habitat recovery
	for m: Dictionary in modifiers:
		if m["kind"] == "per_sol":
			rm.apply_delta(str(m["target"]), int(m["value"]))
	if rm.get_amount("crew_morale") < 20:
		rm.apply_delta("crew_health", -2)
	if habitat_ran and rm.get_amount("crew_morale") >= 50 and _all_supply_above(0.2):
		rm.apply_delta("crew_health", int(get_system_def("habitat").get("crew_health_recovery_per_sol", 1)))
	report["energy_net"] = rm.get_amount("energy") - energy_before

	var shortage: bool = false
	for id: String in SUPPLY:
		if rm.get_ratio(id) < 0.3:
			shortage = true
	if shortage:
		shortage_sols += 1

	last_report = report
	_record_history()

	# 4 — loss check
	var reason: String = _loss_reason()
	if not reason.is_empty():
		_finish(false, reason)
		sol_processed.emit(report)
		return report
	completed_sols = sol

	# 5 — milestones, achievements, objectives
	for ms: Variant in DataLoader.get_mission_progression().get("milestones", []):
		if ms is Dictionary and int(ms.get("sol", -1)) == sol and not milestones_done.has(str(ms.get("id", ""))):
			milestones_done.append(str(ms.get("id", "")))
			_grant(ms.get("reward", {}))
			EventBus.notice.emit("MILESTONE: SOL %d COMPLETE" % sol)
	_check_achievements()
	_update_objectives(true)

	# 6 — tick modifiers and events
	_tick()

	# 7 — finish, or roll and start the next Sol
	sol_processed.emit(report)
	if sol >= GameState.target_sols:
		_finish(true, "")
		return report
	_roll_random_event()
	_start_sol(sol + 1)
	return report


func _tally(d: Dictionary, key: String, amount: int) -> void:
	if amount != 0:
		d[key] = int(d.get(key, 0)) + amount


func _all_supply_above(ratio: float) -> bool:
	for id: String in SUPPLY:
		if ResourceManager.get_ratio(id) < ratio:
			return false
	return true


func _log_fault(text: String) -> void:
	if faults.size() > 40:
		faults.pop_front()
	faults.append(text)


func _record_history() -> void:
	var row: Dictionary = {"sol": sol}
	for id: String in ["energy", "water", "food", "oxygen", "shield", "science", "crew_health", "crew_morale", "base_integrity"]:
		row[id] = ResourceManager.get_amount(id)
	history.append(row)


func _tick() -> void:
	for i: int in range(modifiers.size() - 1, -1, -1):
		var m: Dictionary = modifiers[i]
		if int(m["remaining"]) < 0:
			continue
		m["remaining"] = int(m["remaining"]) - 1
		if int(m["remaining"]) <= 0:
			modifiers.remove_at(i)
			if m["kind"] == "lock":
				_release_lock(m)
			if m["property"] == "capacity_multiplier":
				ResourceManager.set_capacity_multiplier(str(m["target"]), get_multiplier(str(m["target"]), "capacity_multiplier"))
	for i: int in range(active_events.size() - 1, -1, -1):
		var inst: Dictionary = active_events[i]
		inst["remaining"] = int(inst["remaining"]) - 1
		if int(inst["remaining"]) <= 0:
			active_events.remove_at(i)
			events_survived[inst["id"]] = int(events_survived.get(inst["id"], 0)) + 1
			EventBus.game_event_ended.emit(str(inst["id"]))
	state_changed.emit()


func _roll_random_event() -> void:
	var config: Dictionary = DataLoader.get_game_config()
	var scenario: Dictionary = GameState.get_scenario()
	if not bool(scenario.get("random_events_enabled", false)):
		return
	if not active_events.is_empty():
		return
	var next_sol: int = sol + 1
	var week: int = 0
	if GameState.is_story_campaign():
		var pacing: Dictionary = config.get("story_pacing", {})
		if not bool(pacing.get("random_events_in_story_campaign", true)):
			return
		if next_sol < int(pacing.get("no_random_events_before_sol", 3)):
			return
		if bool(pacing.get("skip_roll_when_next_day_is_scripted", true)) \
				and not str(get_story_day(next_sol).get("event_id", "")).is_empty():
			return
		for w: Variant in story.get("weeks", []):
			if w is Dictionary and next_sol >= int(w.get("sol_start", 0)) and next_sol <= int(w.get("sol_end", 0)):
				week = int(w.get("week", 0))
		if int(random_weeks_used.get(week, 0)) >= int(pacing.get("max_random_events_per_week", 1)):
			return
	var roll: Dictionary = config.get("event_roll", {})
	var chance: float = float(roll.get("chance", 0.35)) * GameState.get_event_chance_multiplier()
	if _rng.randf() >= chance:
		return
	var pool: Array = []
	var total: float = 0.0
	for ev: Variant in DataLoader.get_events():
		if ev is Dictionary and str(ev.get("trigger", "")) == "random_event":
			pool.append(ev)
			total += float(ev.get("chance_weight", 1))
	if pool.is_empty():
		return
	var pick: float = _rng.randf() * total
	var chosen: Dictionary = pool[0]
	for ev: Dictionary in pool:
		pick -= float(ev.get("chance_weight", 1))
		if pick <= 0.0:
			chosen = ev
			break
	random_weeks_used[week] = int(random_weeks_used.get(week, 0)) + 1
	var inst: Dictionary = start_event(str(chosen.get("id", "")), "", false)
	if not inst.is_empty():
		_queue({"kind": "event", "event": inst})


## Debug / test hook: force a random event card now.
func debug_trigger_event(event_id: String) -> void:
	var inst: Dictionary = start_event(event_id, "", true)
	if not inst.is_empty():
		_queue({"kind": "event", "event": inst})
		cards_ready.emit()


func _grant(reward: Variant) -> void:
	if reward is Dictionary:
		for key: String in reward:
			ResourceManager.apply_delta(key, int(reward[key]))


func _loss_reason() -> String:
	var rules: Dictionary = DataLoader.get_ending_rules()
	var map: Dictionary = rules.get("defeat", {}).get("failure_reason_map", {})
	for cond: Variant in DataLoader.get_game_config().get("loss_conditions", []):
		var id: String = str(cond).split(" ")[0]
		if ResourceManager.has_type(id) and ResourceManager.get_amount(id) <= 0:
			return str(map.get(id, "%s DEPLETED" % id.to_upper()))
	return ""


func loss_resource() -> String:
	for cond: Variant in DataLoader.get_game_config().get("loss_conditions", []):
		var id: String = str(cond).split(" ")[0]
		if ResourceManager.has_type(id) and ResourceManager.get_amount(id) <= 0:
			return id
	return ""


# ================================================================== conditions

func _ident_value(ident: String) -> float:
	match ident:
		"completed_sol":
			return float(completed_sols)
		"current_sol":
			# Once the last Sol is completed the run counts as having reached the next one.
			return float(sol + 1) if (ended and bool(ending.get("completed", false))) else float(sol)
		"all_critical_systems_enabled":
			for id: String in CRITICAL_SYSTEMS:
				if not is_system_enabled(id):
					return 0.0
			return 1.0
	if ident.begins_with("end_of_sol_"):
		var res: String = ident.substr(11)
		if not history.is_empty():
			return float((history[history.size() - 1] as Dictionary).get(ResourceManager.canonical(res), 0))
		return 0.0
	if ident.ends_with("_enabled") and _systems.has(ident.trim_suffix("_enabled")):
		return 1.0 if is_system_enabled(ident.trim_suffix("_enabled")) else 0.0
	if ResourceManager.has_type(ident):
		return float(ResourceManager.get_amount(ident))
	if counters.has(ident):
		return float(counters[ident])
	return 1.0 if flags.has(ident) else 0.0


func eval_condition(text: String) -> bool:
	for part: String in text.split(" and "):
		if not _eval_term(part.strip_edges()):
			return false
	return true


func _eval_term(term: String) -> bool:
	if term.begins_with("event_survived:"):
		return int(events_survived.get(term.substr(15), 0)) > 0
	for op: String in [">=", "<=", "==", ">", "<"]:
		var at: int = term.find(op)
		if at > 0:
			var left: float = _ident_value(term.substr(0, at).strip_edges())
			var right: float = float(term.substr(at + op.length()).strip_edges())
			match op:
				">=": return left >= right
				"<=": return left <= right
				"==": return is_equal_approx(left, right)
				">": return left > right
				"<": return left < right
	return _ident_value(term) > 0.0


func _check_achievements() -> void:
	for a: Variant in DataLoader.get_achievements():
		if not a is Dictionary:
			continue
		var id: String = str(a.get("id", ""))
		if achievements_unlocked.has(id):
			continue
		if eval_condition(str(a.get("condition", "false_condition"))):
			achievements_unlocked.append(id)
			_grant(a.get("reward", {}))
			EventBus.notice.emit("ACHIEVEMENT: %s" % str(a.get("name", id)).to_upper())


func _build_objectives(scenario: Dictionary) -> void:
	objectives.clear()
	for o: Variant in scenario.get("objectives", []):
		if not o is Dictionary:
			continue
		var cond: String = str(o.get("complete_when", ""))
		var achieve: bool = cond.contains("current_sol") or not (cond.contains(">") or cond.contains("<") or cond.contains("enabled"))
		objectives.append({"id": str(o.get("id", "")), "description": str(o.get("description", "")),
			"condition": cond, "kind": "achieve" if achieve else "maintain", "done": false, "failed": false})


## end_of_sol = true checks "maintain" objectives (they fail the first Sol they break).
func _update_objectives(end_of_sol: bool) -> void:
	for o: Dictionary in objectives:
		if o["kind"] == "achieve":
			if not o["done"] and eval_condition(str(o["condition"])):
				o["done"] = true
				EventBus.notice.emit("OBJECTIVE COMPLETE: %s" % str(o["description"]).to_upper())
		elif end_of_sol and not o["failed"]:
			if not eval_condition(str(o["condition"])):
				o["failed"] = true
	if end_of_sol:
		for o: Dictionary in objectives:
			if o["kind"] == "maintain" and not o["failed"]:
				o["done"] = true


# ================================================================== text tokens

func format_text(text: String) -> String:
	if not text.contains("{"):
		return text
	var low: String = lowest_supply()
	var net: int = int(last_report.get("energy_net", 0))
	var tokens: Dictionary = {
		"{food_days}": str(_days_left("food")), "{water_days}": str(_days_left("water")),
		"{oxygen_days}": str(_days_left("oxygen")), "{science}": str(ResourceManager.get_amount("science")),
		"{science_target}": str(get_science_target()),
		"{lowest_resource}": ResourceManager.get_display_name(low),
		"{lowest_value}": str(ResourceManager.get_amount(low)),
		"{energy}": str(ResourceManager.get_amount("energy")),
		"{energy_trend}": ("%+d per Sol" % net) if not last_report.is_empty() else "not measured yet",
	}
	for key: String in tokens:
		text = text.replace(key, str(tokens[key]))
	return text


func _days_left(res: String) -> int:
	var need: float = float(ResourceManager.get_consumption_per_sol(res)) * GameState.get_resource_multiplier() \
		* get_multiplier(res, "consumption_multiplier")
	if need <= 0.0:
		return 99
	return int(floor(float(ResourceManager.get_amount(res)) / need))


func _diff_text(before: Dictionary, after: Dictionary) -> String:
	var parts: Array = []
	for id: String in ["energy", "oxygen", "water", "food", "shield", "science", "crew_health", "crew_morale", "base_integrity"]:
		var d: int = int(after.get(id, 0)) - int(before.get(id, 0))
		if d != 0:
			parts.append("%s %+d" % [ResourceManager.get_display_name(id), d])
	return "  ·  ".join(parts)


# ================================================================== ending + evaluation

func _finish(completed: bool, reason: String) -> void:
	if ended:
		return
	ended = true
	var state: String = "complete" if completed else "failed"
	GameState.end_mission(state, reason)
	ending = {"completed": completed, "paused": not completed, "reason": reason}
	if completed:
		_update_objectives(false)
		_check_achievements()
		if not GameState.is_story_campaign() and _all_objectives_done():
			_grant(GameState.get_scenario().get("completion_reward", {}))
	evaluation = compute_evaluation(completed)
	var pick: Dictionary = evaluation["ending"]
	pick.merge(ending, true)
	ending = pick
	evaluation["ending"] = ending
	card_queue.clear()
	_queue({"kind": "final", "paused": not completed, "reason": reason})
	run_finished.emit(ending)
	cards_ready.emit()


func _all_objectives_done() -> bool:
	for o: Dictionary in objectives:
		if not o["done"] or o["failed"]:
			return false
	return true


func compute_evaluation(completed: bool) -> Dictionary:
	var rules: Dictionary = DataLoader.get_ending_rules()
	var scoring: Dictionary = rules.get("scoring", {})
	var weight: float = float(scoring.get("decision_point_weight", 2))
	var penalty: float = float(scoring.get("shortage_penalty_per_sol", 3))
	var cat_max: float = float(scoring.get("category_max", 100))
	var states: Dictionary = {}
	var supply: float = 0.0
	for id: String in SUPPLY:
		supply += minf(1.0, ResourceManager.get_ratio(id))
	states["resources"] = supply / float(SUPPLY.size()) * 100.0
	states["safety"] = float(ResourceManager.get_amount("crew_health"))
	states["wellbeing"] = float(ResourceManager.get_amount("crew_morale"))
	states["science"] = minf(100.0, float(ResourceManager.get_amount("science")) / float(maxi(1, get_science_target())) * 100.0)
	states["infrastructure"] = float(ResourceManager.get_amount("base_integrity"))
	var categories: Array = []
	var total_raw: float = 0.0
	var lowest: float = 999.0
	var names: Dictionary = {
		"resources": {"name": "Resource Management", "covers": "Energy, Water, Food and Oxygen"},
		"safety": {"name": "Crew Safety & Health", "covers": "Crew health and radiation protection"},
		"wellbeing": {"name": "Psychological Well-Being", "covers": "Crew morale"},
		"science": {"name": "Scientific Progress", "covers": "Science points against the target"},
		"infrastructure": {"name": "Infrastructure & Maintenance", "covers": "Base integrity and repairs"},
	}
	var story_eval: Variant = story.get("evaluation", {})
	if story_eval is Dictionary:
		for c: Variant in _array((story_eval as Dictionary).get("categories", [])):
			if c is Dictionary:
				names[str(c.get("id", ""))] = c
	for id: Variant in scoring.get("categories", ["resources", "safety", "wellbeing", "science", "infrastructure"]):
		var key: String = str(id)
		var value: float = float(states.get(key, 0.0)) * 0.7 + 30.0 + float(score_points.get(key, 0)) * weight
		if key == "resources":
			value -= float(shortage_sols) * penalty
		var score: int = clampi(roundi(value), 0, int(cat_max))
		total_raw += float(score)
		lowest = minf(lowest, float(score))
		var meta: Dictionary = names.get(key, {})
		categories.append({"id": key, "name": str(meta.get("name", key.capitalize())),
			"covers": str(meta.get("covers", "")), "score": score, "points": int(score_points.get(key, 0))})
	var total_max: float = float(scoring.get("total_max", 1000))
	var count: int = maxi(1, categories.size())
	var total: int = roundi(total_raw * total_max / (cat_max * float(count)))
	var pick: Dictionary = _pick_ending(completed, total, int(lowest))
	return {"categories": categories, "total": total, "total_max": int(total_max), "ending": pick,
		"science": ResourceManager.get_amount("science"), "shortage_sols": shortage_sols,
		"completed_sol": completed_sols}


func _pick_ending(completed: bool, total: int, lowest: int) -> Dictionary:
	var endings: Array = DataLoader.get_ending_rules().get("story_endings", [])
	var by_id: Dictionary = {}
	for e: Variant in endings:
		if e is Dictionary:
			by_id[str(e.get("id", ""))] = e
	if not completed:
		return (by_id.get("mission_paused", {"id": "mission_paused", "title": "MISSION PAUSED"}) as Dictionary).duplicate()
	if GameState.is_story_campaign():
		var req: Dictionary = by_id.get("mission_accomplished", {}).get("requires", {})
		if total >= int(req.get("min_total_score", 700)) and lowest >= int(req.get("min_category_score", 50)) \
				and ResourceManager.get_amount("science") >= int(req.get("min_science_points", 45)):
			return (by_id.get("mission_accomplished", {}) as Dictionary).duplicate()
		return (by_id.get("mission_survived", {}) as Dictionary).duplicate()
	if _all_objectives_done():
		var acc: Dictionary = (by_id.get("mission_accomplished", {}) as Dictionary).duplicate()
		acc["title"] = "SCENARIO COMPLETE"
		acc["text"] = "Every objective of \"%s\" was met." % str(GameState.get_scenario().get("title", ""))
		return acc
	var sur: Dictionary = (by_id.get("mission_survived", {}) as Dictionary).duplicate()
	sur["title"] = "SCENARIO SURVIVED"
	sur["text"] = "The crew made it through \"%s\", but not every objective was met." % str(GameState.get_scenario().get("title", ""))
	return sur
