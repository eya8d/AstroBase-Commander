## scripts/build_menu_layer.gd
## The side build menu ("قائمة البناء الجانبية") the asset pack was drawn for.
##
## It docks the painted BUILD STRUCTURES panel (assets/ui/panels/build_menu_panel.png)
## on the right side of the screen, wires its seven cards to data/buildings.json, writes
## the real cost / power numbers into the slots that the cleanup pass emptied, and turns a
## click into a ghost-placement mode that uses the pack's placement tiles as the marker.
##
## Toggle with B (input action "build_menu"); pick a structure, then click the ground.
## The node builds its own CanvasLayer, so main.tscn only needs node + script.
extends Node

const PANEL_ART := "res://assets/ui/panels/build_menu_panel.png"
## Preloaded rather than referenced by class name: building.gd has no class_name.
const BuildingScript := preload("res://scripts/building.gd")

const SLOT_DIR := "res://assets/ui/build_slots/"
const PLACEMENT_DIR := "res://assets/sprites/building_placement/"
const BUILDING_SCENE := "res://scenes/building.tscn"

## World grid used for placement (matches the painted tile art roughly).
const CELL := 50.0
## Display size of the panel: artwork pixels * PANEL_SCALE.
const PANEL_SCALE := 0.40

## Card rectangles, in build_menu_panel.png pixels (measured from the art).
const CARDS := {
	"solar_panel": Rect2(50, 146, 238, 334),
	"oxygen_generator": Rect2(300, 148, 230, 320),
	"water_extraction": Rect2(551, 150, 228, 312),
	"greenhouse": Rect2(795, 150, 229, 307),
	"crew_habitat": Rect2(188, 475, 218, 325),
	"shield_generator": Rect2(435, 478, 222, 322),
	"research_lab": Rect2(681, 478, 214, 312),
}
## The COST/POWER band inside each card.  Measured on the restored artwork with
## .work/scripts/text_runs.ps1: the top row paints "COST: [icons] / POWER: [+/-]" at
## y 373..433 and the bottom row at y 690..750, so these plates have to cover the whole
## band or the invented icon costs show through behind the live numbers.
const CARD_TEXT := {
	# Widened to almost the full card so a line like "COST: 10 ORE · 5 WATER" fits
	# without the centred Label clipping its first and last character.
	"solar_panel": Rect2(62, 367, 214, 76),
	"oxygen_generator": Rect2(312, 367, 206, 76),
	"water_extraction": Rect2(563, 367, 204, 76),
	"greenhouse": Rect2(807, 367, 205, 76),
	"crew_habitat": Rect2(200, 693, 196, 74),
	"shield_generator": Rect2(447, 693, 198, 74),
	"research_lab": Rect2(693, 693, 190, 74),
}
## The painted close "X" in the top-right corner.
const CLOSE_RECT := Rect2(968, 32, 90, 82)

const RES_ABBR := {
	"ore": "ORE", "water": "WATER", "energy": "PWR", "oxygen": "O2",
	"food": "FOOD", "shield": "SHLD", "science": "SCI",
}

var _layer: CanvasLayer
var _root: Control
var _panel: Control
var _selection_frame: Panel
var _card_buttons: Dictionary = {}
var _card_texts: Dictionary = {}
var _building_data: Dictionary = {}    # id -> row from buildings.json
var _menu_open: bool = false

# --- placement mode ---
var _placing_id: String = ""
var _ghost_root: Node2D
var _ghost_sprite: Sprite2D
var _frame_valid: Sprite2D
var _frame_invalid: Sprite2D
var _cell := Vector2i.ZERO
var _cell_valid := false


func _ready() -> void:
	for row: Dictionary in DataLoader.get_buildings():
		var id: String = str(row.get("id", ""))
		if not id.is_empty():
			_building_data[id] = row

	_layer = CanvasLayer.new()
	_layer.name = "BuildMenuCanvas"
	_layer.layer = 7
	add_child(_layer)

	_root = Control.new()
	_root.name = "BuildMenuRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_root)

	_build_panel()
	_build_ghost()
	_open(false)


# ==================== panel ====================

func _build_panel() -> void:
	var art := load(PANEL_ART) as Texture2D
	if art == null:
		push_warning("build_menu_layer: missing %s" % PANEL_ART)
		return
	_panel = UiRegions.add_artwork_panel(_root, art, PANEL_SCALE, "BuildPanel")
	# Dock on the right edge, vertically centred, instead of modal-centred.
	_panel.position = Vector2(1280.0 - art.get_width() * PANEL_SCALE - 10.0,
			(720.0 - art.get_height() * PANEL_SCALE) * 0.5)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Selection highlight that follows the hovered / chosen card.
	_selection_frame = Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.25, 0.8, 1.0, 0.10)
	style.border_color = Color(0.35, 0.9, 1.0, 0.95)
	style.set_border_width_all(4)
	style.set_corner_radius_all(10)
	_selection_frame.add_theme_stylebox_override("panel", style)
	_selection_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selection_frame.visible = false
	_panel.add_child(_selection_frame)

	for id: String in CARDS:
		if not _building_data.has(id):
			continue        # the art has a card the data does not describe yet
		var card: Rect2 = CARDS[id]
		var button := Button.new()
		button.name = "Card_" + id
		button.position = card.position
		button.size = card.size
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		var empty := StyleBoxFlat.new()
		empty.bg_color = Color(0, 0, 0, 0)
		button.add_theme_stylebox_override("normal", empty)
		var hover := StyleBoxFlat.new()
		hover.bg_color = Color(0.35, 0.85, 1.0, 0.10)
		hover.border_color = Color(0.35, 0.9, 1.0, 0.5)
		hover.set_border_width_all(3)
		hover.set_corner_radius_all(10)
		button.add_theme_stylebox_override("hover", hover)
		button.add_theme_stylebox_override("pressed", hover)
		_panel.add_child(button)
		_card_buttons[id] = button
		button.mouse_entered.connect(_on_card_hover.bind(id))
		button.mouse_exited.connect(_on_card_unhover)
		button.pressed.connect(_on_card_pressed.bind(id))

		# Real cost / power printed into the flattened band.
		var text_rect: Rect2 = CARD_TEXT[id]
		# The artwork paints "COST: [gear][bolt]" and "POWER: [+/-]" in these slots, so
		# the plate hides that invented cost and the live numbers print on top of it —
		# the same mechanism the HUD read-outs use.
		var label := UiRegions.add_label(_panel, text_rect, 17, Color(0.94, 0.97, 1.0),
			HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, false, true)
		_card_texts[id] = label
		_refresh_card_text(id)

	var close := UiRegions.add_region_button(_panel, art, CLOSE_RECT, "CloseButton")
	if close != null:
		close.pressed.connect(func() -> void: _open(false))

	# The cropped slot icons (assets/ui/build_slots/*.png) are kept as the hover
	# preview inside the structure-details panel, so nothing is wasted.
	_refresh_all_cards()


func _refresh_card_text(id: String) -> void:
	var label: Label = _card_texts.get(id)
	if label == null:
		return
	var row: Dictionary = _building_data[id]
	var cost: Dictionary = row.get("build_cost", {}) as Dictionary
	var parts := PackedStringArray()
	for res: String in cost:
		parts.append("%d %s" % [int(cost[res]), String(RES_ABBR.get(res, res.to_upper()))])
	var power: int = int(row.get("power_per_sol", 0))
	var power_text: String = ("+%d kW/Sol" % power) if power > 0 else ("%d kW/Sol" % power)
	var cost_text: String = " · ".join(parts) if not parts.is_empty() else "FREE"
	label.text = "COST: %s\nPOWER: %s" % [cost_text, power_text]
	var affordable: bool = ResourceManager.has_enough(cost)
	label.add_theme_color_override("font_color",
		Color(0.94, 0.97, 1.0) if affordable else Color(1.0, 0.45, 0.4))


func _refresh_all_cards() -> void:
	for id: String in _card_texts:
		_refresh_card_text(id)


func _on_card_hover(id: String) -> void:
	AudioManager.play_ui_hover()
	_selection_frame.visible = true
	_selection_frame.position = CARDS[id].position
	_selection_frame.size = CARDS[id].size
	EventBus.build_menu_focus.emit(id)


func _on_card_unhover() -> void:
	if _placing_id.is_empty():
		_selection_frame.visible = false
	EventBus.build_menu_focus.emit("")


func _on_card_pressed(id: String) -> void:
	AudioManager.play_ui_confirm()
	_begin_placement(id)


# ==================== open / close ====================

func _open(value: bool) -> void:
	_menu_open = value
	_panel.visible = value
	if not value:
		_selection_frame.visible = false
		if _placing_id.is_empty():
			_ghost_root.visible = false


func is_open() -> bool:
	return _menu_open


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("build_menu"):
		_open(not _menu_open)
		if _menu_open:
			_refresh_all_cards()
		get_viewport().set_input_as_handled()


## ESC during placement cancels the ghost instead of opening the pause menu.
## Returns true when the key press was consumed here.
func cancel_placement() -> bool:
	if _placing_id.is_empty():
		return false
	_end_placement()
	return true


## Called by the STRUCTURE DETAILS panel's BUILD button.
func start_placement(id: String) -> void:
	if _building_data.has(id):
		_open(true)
		_begin_placement(id)


# ==================== placement ====================

func _build_ghost() -> void:
	_ghost_root = Node2D.new()
	_ghost_root.name = "PlacementGhost"
	_ghost_root.z_index = 8
	_ghost_root.visible = false
	# Main is still building its own children while this script's _ready() runs,
	# so the ghost has to join the tree one frame later.
	get_parent().add_child.call_deferred(_ghost_root)

	# Green/cyan bracket for a legal cell, red for an occupied one.
	_frame_valid = Sprite2D.new()
	_frame_valid.name = "FrameValid"
	_frame_valid.texture = load(PLACEMENT_DIR + "placement_tile_53.png")
	_frame_valid.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_frame_valid.modulate = Color(1, 1, 1, 0.85)
	_ghost_root.add_child(_frame_valid)

	_frame_invalid = Sprite2D.new()
	_frame_invalid.name = "FrameInvalid"
	_frame_invalid.texture = load(PLACEMENT_DIR + "placement_tile_42.png")
	_frame_invalid.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_frame_invalid.modulate = Color(1, 1, 1, 0.85)
	_frame_invalid.visible = false
	_ghost_root.add_child(_frame_invalid)

	_ghost_sprite = Sprite2D.new()
	_ghost_sprite.name = "BuildingGhost"
	_ghost_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ghost_root.add_child(_ghost_sprite)


func _begin_placement(id: String) -> void:
	_placing_id = id
	var row: Dictionary = _building_data[id]
	var art: Dictionary = BuildingScript.BUILDING_ART.get(id, {}) as Dictionary
	var path: String = str(art.get("on", art.get("off", "")))
	_ghost_sprite.texture = load(path) if not path.is_empty() else null
	_ghost_sprite.scale = BuildingScript.BUILDING_ART_SCALE
	_ghost_sprite.modulate = Color(1, 1, 1, 0.6)

	var cells: Array = row.get("grid_cells", [1, 1]) as Array
	var w: float = float(int(cells[0])) * CELL
	var h: float = float(int(cells[1])) * CELL
	for frame: Sprite2D in [_frame_valid, _frame_invalid]:
		frame.scale = Vector2(w / 125.0, h / 124.0)

	_ghost_root.visible = true
	_selection_frame.visible = true
	_selection_frame.position = CARDS[id].position
	_selection_frame.size = CARDS[id].size
	EventBus.notice.emit("CLICK THE GROUND TO PLACE · ESC TO CANCEL")


func _end_placement() -> void:
	_placing_id = ""
	_ghost_root.visible = false
	if _menu_open:
		_selection_frame.visible = false


func is_placement_active() -> bool:
	return not _placing_id.is_empty()


func _unhandled_input(event: InputEvent) -> void:
	if not is_placement_active():
		return
	if get_tree().paused:
		return

	if event is InputEventMouseMotion:
		_update_ghost_position()
	elif event.is_action_pressed("cancel") or (
			event is InputEventMouseButton and event.pressed
			and event.button_index == MOUSE_BUTTON_RIGHT):
		_end_placement()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_try_place()
		get_viewport().set_input_as_handled()


func _world_mouse() -> Vector2:
	var canvas_xf: Transform2D = get_viewport().get_canvas_transform()
	return canvas_xf.affine_inverse() * get_viewport().get_mouse_position()


func _footprint_cells() -> Vector2i:
	var row: Dictionary = _building_data.get(_placing_id, {})
	var cells: Array = row.get("grid_cells", [1, 1]) as Array
	return Vector2i(int(cells[0]), int(cells[1]))


func _cell_top_left(mouse_world: Vector2) -> Vector2i:
	var cells := _footprint_cells()
	# Snap the whole footprint around the cursor so big buildings centre on it.
	return Vector2i(
		roundi((mouse_world.x / CELL) - cells.x * 0.5),
		roundi((mouse_world.y / CELL) - cells.y * 0.5)
	)


func _update_ghost_position() -> void:
	var mouse_world := _world_mouse()
	_cell = _cell_top_left(mouse_world)
	var cells := _footprint_cells()
	var center := (Vector2(_cell) + Vector2(cells) * 0.5) * CELL
	_ghost_root.position = center
	_cell_valid = _cell_is_legal(center, cells)
	_frame_valid.visible = _cell_valid
	_frame_invalid.visible = not _cell_valid
	_ghost_sprite.modulate = Color(0.6, 1.0, 0.7, 0.65) if _cell_valid \
		else Color(1.0, 0.45, 0.45, 0.65)


## Legal = inside the arena, not overlapping a wall / rock / building, and affordable.
func _cell_is_legal(center: Vector2, cells: Vector2i) -> bool:
	var size := Vector2(cells) * CELL
	var bounds := Rect2(Vector2(size.x * 0.5, size.y * 0.5), Vector2(2000, 1200) - size)
	if not bounds.has_point(center):
		return false
	var row: Dictionary = _building_data.get(_placing_id, {}) as Dictionary
	var cost: Dictionary = row.get("build_cost", {}) as Dictionary
	if not ResourceManager.has_enough(cost):
		return false

	var shape := RectangleShape2D.new()
	shape.size = size - Vector2(10, 10)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, center)
	# layer 1 = walls, solid props, existing building footprints
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var main := get_parent() as Node2D
	if main == null:
		return false
	var hits: Array = main.get_world_2d().direct_space_state.intersect_shape(query, 4)
	return hits.is_empty()


func _try_place() -> void:
	if _placing_id.is_empty():
		return
	var row: Dictionary = _building_data[_placing_id] as Dictionary
	var cells := _footprint_cells()
	var center := (Vector2(_cell) + Vector2(cells) * 0.5) * CELL
	if not _cell_is_legal(center, cells):
		EventBus.notice.emit("CANNOT BUILD HERE")
		return

	var cost: Dictionary = row.get("build_cost", {}) as Dictionary
	if not ResourceManager.spend(cost):
		_refresh_all_cards()
		EventBus.notice.emit("NOT ENOUGH RESOURCES")
		return

	var scene := load(BUILDING_SCENE) as PackedScene
	if scene == null:
		push_warning("build_menu_layer: missing %s" % BUILDING_SCENE)
		return
	var building: Node2D = scene.instantiate()
	building.set("building_id", _placing_id)
	building.set("start_on", true)
	building.position = center
	get_parent().add_child(building)

	EventBus.building_placed.emit(_placing_id, _cell)
	_refresh_all_cards()
	# Keep the mode active so a whole row can be built in one go.
	_update_ghost_position()
