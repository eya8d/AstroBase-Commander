## scripts/game_state.gd
## Autoload: the few values the menu flow and the mission need to agree on.
## WHY: the start-mission briefing screen sets the mission length, the Sol clock
##      needs the speed, and the overlays need to know a mission is in progress.
extends Node

## Real seconds per Sol (Martian day).  The briefing screen can change it.
## Three minutes felt right while playing: long enough that an event (one to three Sols)
## is something you actually live through, short enough that nothing ever goes idle.
var sol_seconds: float = 180.0

## Sols needed to finish the mission (the briefing art says 30 SOLS).
var target_sols: int = 30

## True once START MISSION was pressed, so overlays know they are in a run.
var mission_running: bool = false

## Last mission result: "" | "complete" | "failed"
var mission_result: String = ""

## Why a mission ended, for the failure report screen.
var result_reason: String = ""

## Show the old text debug read-out (toggled with F2).
var show_debug_text: bool = false


func begin_mission() -> void:
	mission_running = true
	mission_result = ""
	result_reason = ""


func end_mission(state: String, reason: String) -> void:
	mission_running = false
	mission_result = state
	result_reason = reason
