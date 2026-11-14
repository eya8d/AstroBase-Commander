## scripts/game_state.gd
## Autoload: the settings the menu flow and the mission agree on — landing site,
## scenario, difficulty and Sol length.  The running rules live in Mission
## (scripts/mission.gd); this file only says *what* run to start.
extends Node

const CAMPAIGN_ID := "scenario_30_sol_campaign"

## Real seconds per Sol. game_config.json -> sol_length_seconds_default (90 s =
## QUICK, the demo default; Settings offers STANDARD 180 s and RELAXED 240 s).
var sol_seconds: float = 90.0

## Last Sol of the run (30 for the campaign, a scenario's end_sol otherwise).
var target_sols: int = 30

## True once START MISSION was pressed, so overlays know they are in a run.
var mission_running: bool = false

## Last result: "" | "complete" | "failed"
var mission_result: String = ""
var result_reason: String = ""

## Show the text debug read-out (F2).
var show_debug_text: bool = false

## Day 0: the site confirmed on the landing map ("" = none).
var landing_site_id: String = ""
var landing_site: Dictionary = {}

## Mission picked on the briefing screen (scenarios/scenarios.json id).
var scenario_id: String = CAMPAIGN_ID
## "easy" | "normal" | "hard" (game_config.json -> difficulty.levels).
var difficulty: String = "normal"


func _ready() -> void:
	var config: Dictionary = DataLoader.get_game_config()
	sol_seconds = float(config.get("sol_length_seconds_default", sol_seconds))
	var diff: Variant = config.get("difficulty", {})
	if diff is Dictionary:
		difficulty = str((diff as Dictionary).get("default", difficulty))
	_apply_scenario_length()


# ------------------------------------------------------------------ landing site

func select_landing_site(site_id: String) -> bool:
	var site: Dictionary = DataLoader.get_landing_site(site_id)
	if site.is_empty() or not bool(site.get("available", false)):
		push_warning("GameState: landing site '%s' is not available" % site_id)
		return false
	landing_site_id = site_id
	landing_site = site
	return true


func get_landing_site_name() -> String:
	return str(landing_site.get("name", ""))


## A gameplay rule of the chosen site (solar_output, water_ice_yield, build_ore_cost).
## Game-design values from the "gameplay" block, never NASA measurements.
func get_site_modifier(key: String, default_value: float = 1.0) -> float:
	var rules: Variant = landing_site.get("gameplay", {})
	if rules is Dictionary:
		return float((rules as Dictionary).get(key, default_value))
	return default_value


func get_site_ground_texture() -> String:
	return str(landing_site.get("ground_texture", ""))


## Starting stores: resources.json defaults <- landing site <- scenario overrides.
func get_starting_resources() -> Dictionary:
	var start: Dictionary = {}
	var defaults: Variant = DataLoader.get_landing_catalogue().get("default_starting_resources", {})
	if defaults is Dictionary:
		start.merge(defaults, true)
	var rules: Variant = landing_site.get("gameplay", {})
	if rules is Dictionary:
		var site_start: Variant = (rules as Dictionary).get("starting_resources", {})
		if site_start is Dictionary:
			start.merge(site_start, true)
	var overrides: Variant = get_scenario().get("starting_resource_overrides", {})
	if overrides is Dictionary:
		start.merge(overrides, true)
	return start


func adjust_build_cost(cost: Dictionary) -> Dictionary:
	var result: Dictionary = cost.duplicate()
	if result.has("ore"):
		var base: int = int(result["ore"])
		if base > 0:
			result["ore"] = maxi(1, ceili(float(base) * get_site_modifier("build_ore_cost", 1.0)))
	return result


# ------------------------------------------------------------------ scenario / difficulty

func set_scenario(id: String) -> void:
	if DataLoader.get_scenario(id).is_empty():
		push_warning("GameState: unknown scenario '%s'" % id)
		return
	scenario_id = id
	_apply_scenario_length()


func get_scenario() -> Dictionary:
	return DataLoader.get_scenario(scenario_id)


func is_story_campaign() -> bool:
	return scenario_id == CAMPAIGN_ID


func get_start_sol() -> int:
	return int(get_scenario().get("start_sol", 1))


func set_difficulty(level: String) -> void:
	if get_difficulty_levels().has(level):
		difficulty = level


func get_difficulty_levels() -> Dictionary:
	var diff: Variant = DataLoader.get_game_config().get("difficulty", {})
	if diff is Dictionary:
		var levels: Variant = (diff as Dictionary).get("levels", {})
		if levels is Dictionary:
			return levels
	return {"normal": {"resource_multiplier": 1.0, "event_chance_multiplier": 1.0}}


## resource_multiplier scales daily consumption and event damage.
func get_resource_multiplier() -> float:
	return float(get_difficulty_levels().get(difficulty, {}).get("resource_multiplier", 1.0))


## event_chance_multiplier scales the 0.35 end-of-Sol roll.
func get_event_chance_multiplier() -> float:
	return float(get_difficulty_levels().get(difficulty, {}).get("event_chance_multiplier", 1.0))


func _apply_scenario_length() -> void:
	target_sols = int(get_scenario().get("end_sol", 30))


# ------------------------------------------------------------------ run lifecycle

## A new run (first start or restart): stores and mission rules go back to the start.
func begin_mission() -> void:
	mission_running = true
	mission_result = ""
	result_reason = ""
	_apply_scenario_length()
	ResourceManager.reset_to(get_starting_resources())
	Mission.begin_run()


func end_mission(state: String, reason: String) -> void:
	mission_running = false
	mission_result = state
	result_reason = reason
