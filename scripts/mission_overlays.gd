## scripts/mission_overlays.gd
## The end-of-mission screens, straight from the pack:
##   assets/ui/screens/mission_complete.png  — the target Sol was reached
##   assets/ui/screens/mission_failed.png    — oxygen ran out
##
## The painted read-outs on those screens were placeholders, so the cleanup pass
## (.work/scripts/polish_ui5.ps1) wiped them and this script writes the player's real
## numbers into the same slots.  Both buttons on each screen are cut out of the artwork
## and are real controls.
extends Node

const COMPLETE_ART := "res://assets/ui/screens/mission_complete.png"
const FAILED_ART := "res://assets/ui/screens/mission_failed.png"

## All rects below are in the screens' 1376x768 pixel space.
const BTN_CONTINUE := Rect2(345, 648, 336, 89)
const BTN_COMPLETE_MENU := Rect2(712, 645, 333, 90)
const BTN_RETRY := Rect2(345, 640, 336, 97)
const BTN_FAILED_MENU := Rect2(712, 645, 336, 90)

const ROW_ENERGY := Rect2(1105, 283, 178, 48)
const ROW_ATMOSPHERE := Rect2(1105, 338, 178, 48)
const ROW_RADIATION := Rect2(1105, 393, 178, 48)

const FAIL_SOL := Rect2(975, 138, 178, 50)
const FAIL_CAUSE := Rect2(800, 285, 448, 52)
const FAIL_ATMOSPHERE := Rect2(800, 341, 448, 52)
const FAIL_BATTERY := Rect2(800, 397, 448, 52)

const ART_SIZE := Vector2(1376, 768)
const CREAM := Color(0.95, 0.9, 0.8)
const ORANGE := Color(1.0, 0.72, 0.35)

var _root: Control
var _art: TextureRect
var _printed: Array[Control] = []
var _buttons: Array[TextureButton] = []
var _result_open: bool = false


func _ready() -> void:
	# Must stay alive while the tree is paused by the result screen.
	process_mode = Node.PROCESS_MODE_ALWAYS

	var layer := CanvasLayer.new()
	layer.name = "MissionCanvas"
	layer.layer = 15
	add_child(layer)

	_root = Control.new()
	_root.name = "ResultRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	layer.add_child(_root)

	_art = UiRegions.add_fullscreen_art(_root, null, "ResultArt")
	EventBus.mission_over.connect(_show)


func is_open() -> bool:
	return _result_open


## Called by the Sol processor the moment the mission ends.
func _show(state: String, reason: String) -> void:
	if state.is_empty():
		_hide()
		return

	for control: Control in _printed:
		control.queue_free()
	_printed.clear()
	for button: TextureButton in _buttons:
		button.queue_free()
	_buttons.clear()

	var art := load(COMPLETE_ART if state == "complete" else FAILED_ART) as Texture2D
	_art.texture = art
	_root.visible = true
	_result_open = true
	get_tree().paused = true

	var report := _mission_report(reason)
	if state == "complete":
		# The artwork paints the square brackets itself outside these slots, so the
		# runtime value must not repeat them.
		_print(ROW_ENERGY, "%d%%" % report["efficiency"])
		_print(ROW_ATMOSPHERE, "%d%%" % report["oxygen"])
		_print(ROW_RADIATION, "%d%%" % report["shield"])
		_button(art, BTN_CONTINUE, "Continue", _on_continue)
		_button(art, BTN_COMPLETE_MENU, "ToMenu", _to_menu)
	else:
		_print(FAIL_SOL, "%02d" % report["sol"], 30, CREAM)
		_print(FAIL_CAUSE, "[ FAILURE CAUSE: %s ]" % reason.to_upper(), 30, CREAM,
			HORIZONTAL_ALIGNMENT_LEFT)
		_print(FAIL_ATMOSPHERE, "[ ATMOSPHERIC LEVELS: %s ]"
			% ("STABLE" if report["oxygen"] > 25 else "DEPLETED"), 30, CREAM,
			HORIZONTAL_ALIGNMENT_LEFT)
		_print(FAIL_BATTERY, "[ BATTERY RESERVES: %s ]"
			% ("0%% CRITICAL" if report["energy"] <= 0 else "%d kW LEFT" % report["energy"]),
			30, ORANGE, HORIZONTAL_ALIGNMENT_LEFT)
		_button(art, BTN_RETRY, "Retry", _retry)
		_button(art, BTN_FAILED_MENU, "ToMenu", _to_menu)


func _hide() -> void:
	_result_open = false
	_root.visible = false
	get_tree().paused = false


## Numbers the two screens report, taken from the running game (no fake stats).
func _mission_report(_reason: String) -> Dictionary:
	var main: Node = get_parent()
	var stats: Dictionary = main.get_power_stats() if main.has_method("get_power_stats") else {}
	var produced: int = int(stats.get("produced", 0))
	var needed: int = int(stats.get("needed", 0))
	var efficiency: int = 100 if needed <= 0 else int(round(100.0 * produced / float(needed)))
	return {
		"sol": int(main.get_current_sol()) if main.has_method("get_current_sol") else 0,
		"oxygen": clampi(ResourceManager.get_amount("oxygen"), 0, 100),
		"shield": clampi(ResourceManager.get_amount("shield"), 0, 100),
		"energy": ResourceManager.get_amount("energy"),
		"efficiency": clampi(efficiency, 0, 199),
	}


## Prints one runtime value inside an artwork-pixel rect.
func _print(rect: Rect2, text: String, font_size: int = 34,
		color: Color = CREAM, halign: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var k := _root.size / ART_SIZE
	var label := UiRegions.add_label(_root, Rect2(rect.position * k, rect.size * k),
		int(round(float(font_size) * k.y)), color, halign)
	label.name = "Printed_%s" % text.left(12).replace(" ", "_")
	label.text = text
	_printed.append(label)


func _button(art: Texture2D, region: Rect2, name_hint: String, callback: Callable) -> void:
	var button := UiRegions.add_region_button(_root, art, region, name_hint)
	if button != null:
		button.pressed.connect(callback)
		_buttons.append(button)


func _on_continue() -> void:
	# Endless mode: the colony stays open and the target moves by another 10 Sols.
	GameState.target_sols += 10
	GameState.mission_running = true
	GameState.mission_result = ""
	_hide()


func _retry() -> void:
	get_tree().paused = false
	GameState.begin_mission()
	get_tree().reload_current_scene()


func _to_menu() -> void:
	get_tree().paused = false
	GameState.mission_running = false
	get_tree().change_scene_to_file("res://scenes/menu_main.tscn")
