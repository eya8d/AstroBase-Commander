## scripts/event_bus.gd
## Global signal bus. Every system emits and connects through here,
## so no script needs a direct reference to another script.
## Signals only — no logic, no state.
extends Node

# --- Resource Collection ---
@warning_ignore("unused_signal")
signal item_collected(type: String, amount: int)

# --- Building System ---
@warning_ignore("unused_signal")
signal building_placed(building_id: String, cell: Vector2i)

@warning_ignore("unused_signal")
signal building_toggled(building_id: String, is_on: bool)

# --- Farming ---
@warning_ignore("unused_signal")
signal crop_harvested(crop_id: String, amount: int)

# --- Sol (Day) Clock ---
@warning_ignore("unused_signal")
signal day_changed(day: int)

# --- Random Events ---
@warning_ignore("unused_signal")
signal game_event_started(event: Dictionary)

@warning_ignore("unused_signal")
signal game_event_ended(event_id: String)

# --- Space Weather ---
@warning_ignore("unused_signal")
signal space_weather_warning(event: Dictionary)

@warning_ignore("unused_signal")
signal space_weather_resolved(result: Dictionary)

# --- Education / Facts ---
@warning_ignore("unused_signal")
signal fact_unlocked(fact: Dictionary)

# --- Pack v2 interface (added when the asset pack was wired in) ---

## Short HUD toast text (assets/ui/hud/notification_toast.png).
@warning_ignore("unused_signal")
signal notice(text: String)

## The pointer is hovering this building id in the build menu ("" = left it),
## which opens the painted STRUCTURE DETAILS panel.
@warning_ignore("unused_signal")
signal build_menu_focus(building_id: String)

## Mission finished: state is "complete" or "failed".
@warning_ignore("unused_signal")
signal mission_over(state: String, reason: String)
