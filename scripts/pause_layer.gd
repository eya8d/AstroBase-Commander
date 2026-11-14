## scripts/pause_layer.gd
## ESC opens the painted MISSION PAUSED panel (assets/ui/panels/pause_menu.png).
## The three buttons are cut straight out of the artwork, so the overlay looks exactly
## like the concept art while being fully functional: resume, restart, main menu.
extends Node

const ART := "res://assets/ui/panels/pause_menu.png"
const SCALE := 0.66

## Button regions in pause_menu.png pixels.
const BTN_RESUME := Rect2(250, 258, 360, 102)
const BTN_RESTART := Rect2(255, 398, 357, 102)
const BTN_MAIN := Rect2(248, 528, 377, 134)
## The "[ TACTICAL SUSPENSION // SOL -- ]" band whose number was flattened.
const SOL_RECT := Rect2(588, 184, 104, 48)

var _layer: CanvasLayer
var _dim: ColorRect
var _holder: Control
var _sol_label: Label
var _is_open: bool = false


func _ready() -> void:
	# The overlay must keep working while the whole tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_layer = CanvasLayer.new()
	_layer.name = "PauseCanvas"
	_layer.layer = 12
	add_child(_layer)

	_dim = ColorRect.new()
	_dim.color = Color(0.01, 0.02, 0.05, 0.72)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	_layer.add_child(_dim)

	var art := load(ART) as Texture2D
	if art == null:
		push_warning("pause_layer: missing %s" % ART)
		return

	_holder = UiRegions.add_artwork_panel(_dim, art, SCALE)
	_holder.position = (Vector2(1280, 720) - Vector2(art.get_width(), art.get_height()) * SCALE) * 0.5
	_holder.visible = false

	_sol_label = UiRegions.add_label(_holder, SOL_RECT, 34, Color(0.45, 0.85, 0.95))

	var resume := UiRegions.add_region_button(_holder, art, BTN_RESUME, "Resume")
	if resume != null:
		resume.pressed.connect(close)
	var restart := UiRegions.add_region_button(_holder, art, BTN_RESTART, "Restart")
	if restart != null:
		restart.pressed.connect(_restart)
	var main := UiRegions.add_region_button(_holder, art, BTN_MAIN, "ToMenu")
	if main != null:
		main.pressed.connect(_to_menu)


func is_open() -> bool:
	return _is_open


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("cancel"):
		return
	if _is_open:
		close()
		get_viewport().set_input_as_handled()
		return
	# A placement ghost has priority over the pause menu.
	var menu: Node = get_parent().get_node_or_null("BuildMenuLayer")
	if menu != null and menu.has_method("cancel_placement") and bool(menu.cancel_placement()):
		get_viewport().set_input_as_handled()
		return
	var panels: Node = get_parent().get_node_or_null("PanelsLayer")
	if panels != null and bool(panels.get("_data_open")):
		return
	var overlays: Node = get_parent().get_node_or_null("MissionOverlays")
	if overlays != null and bool(overlays.get("_result_open")):
		return
	open()


func open() -> void:
	_is_open = true
	_dim.visible = true
	_holder.visible = true
	_show_sol()
	get_tree().paused = true


func close() -> void:
	_is_open = false
	_dim.visible = false
	_holder.visible = false
	get_tree().paused = false


## Shows the Sol clock value inside the painted band.
func _show_sol() -> void:
	var main: Node = get_parent()
	if main.has_method("get_current_sol"):
		_sol_label.text = "%02d" % int(main.get_current_sol())


func _restart() -> void:
	get_tree().paused = false
	GameState.begin_mission()
	get_tree().reload_current_scene()


func _to_menu() -> void:
	get_tree().paused = false
	GameState.mission_running = false
	get_tree().change_scene_to_file("res://scenes/menu_main.tscn")
