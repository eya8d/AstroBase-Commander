## scripts/player.gd
## Player controller: 8-direction movement, camera, and unified interaction.
## The InteractionArea detects nearby objects in group "interactable".
## On E press, the NEAREST one gets its interact(player) called.
extends CharacterBody2D

## 180 px/s at 2x zoom: about 12 s to cross the 2064 px site.
@export var speed: float = 180.0
@export var can_move: bool = true

@export_group("Camera Limits")
@export var camera_limit_left: int = 0
@export var camera_limit_top: int = 0
@export var camera_limit_right: int = 2064
@export var camera_limit_bottom: int = 1152
## Tighter point of view: 2x shows 640x360 world pixels (3 screen px per map px).
@export var camera_zoom: float = 2.0

@onready var sprite: AnimatedSprite2D = $Sprite2D
@onready var camera: Camera2D = $Camera2D
@onready var interaction_area: Area2D = $InteractionArea

const IDLE_SOUTH_SCALE := Vector2(0.09, 0.09)
const ACTION_SCALES := {
	&"collect_water": Vector2(0.28, 0.28),
	&"mine_hammer": Vector2(0.28, 0.28),
	&"interact_building": Vector2(0.28, 0.28),
	&"clean_solar_panel": Vector2(0.28, 0.28),
}
const SOLAR_CLEANING_SHEET_PATH := "res://assets/player/animations/solar_panel_cleaning_sheet.png"
const SOLAR_CLEANING_FRAME_SIZE := Vector2i(256, 256)
const SOLAR_CLEANING_SHEET_COLUMNS := 5
const SOLAR_CLEANING_FRAME_COUNT := 25
const WALK_SCALES := {
	&"walk_down": Vector2(0.25, 0.25),
	&"walk_up": Vector2(0.25, 0.25),
	&"walk_right": Vector2(0.27, 0.27),
	&"walk_left": Vector2(0.235, 0.235),
	&"walk_up_right": Vector2(0.257, 0.257),
	&"walk_up_left": Vector2(0.257, 0.257),
	&"walk_down_right": Vector2(0.235, 0.235),
	&"walk_down_left": Vector2(0.235, 0.235),
}

# The supplied artwork includes a south-facing idle only. Other directions hold
# their last walk frame while stopped, preserving the last facing direction.
var _last_facing_animation: StringName = &"walk_down"
var _active_action_animation: StringName = &""

# All interactable Area2Ds currently overlapping our InteractionArea.
var _nearby_interactables: Array = []
# The one we would interact with if the player presses E right now.
var _current_target: Node = null


func _ready() -> void:
	if sprite:
		_install_solar_cleaning_animation()
		sprite.scale = IDLE_SOUTH_SCALE
		sprite.play(&"idle_down")
		sprite.stop()
		sprite.animation_finished.connect(_on_sprite_animation_finished)

	if camera:
		camera.zoom = Vector2(camera_zoom, camera_zoom)
		camera.limit_left = camera_limit_left
		camera.limit_top = camera_limit_top
		camera.limit_right = camera_limit_right
		camera.limit_bottom = camera_limit_bottom

	if interaction_area:
		interaction_area.area_entered.connect(_on_interaction_area_entered)
		interaction_area.area_exited.connect(_on_interaction_area_exited)


func _install_solar_cleaning_animation() -> void:
	if not sprite or not sprite.sprite_frames:
		return
	if sprite.sprite_frames.has_animation(&"clean_solar_panel"):
		return

	var sheet := load(SOLAR_CLEANING_SHEET_PATH) as Texture2D
	if sheet == null:
		push_warning("Player: missing solar cleaning animation sheet: %s" % SOLAR_CLEANING_SHEET_PATH)
		return

	# Keep the scene's shared SpriteFrames resource unchanged for other instances.
	var frames := sprite.sprite_frames.duplicate() as SpriteFrames
	if frames == null:
		push_warning("Player: could not duplicate the player SpriteFrames resource.")
		return
	sprite.sprite_frames = frames
	frames.add_animation(&"clean_solar_panel")
	frames.set_animation_speed(&"clean_solar_panel", 12.0)
	frames.set_animation_loop(&"clean_solar_panel", false)
	for frame_index: int in range(SOLAR_CLEANING_FRAME_COUNT):
		var column: int = frame_index % SOLAR_CLEANING_SHEET_COLUMNS
		var row: int = floori(float(frame_index) / float(SOLAR_CLEANING_SHEET_COLUMNS))
		var frame_texture := AtlasTexture.new()
		frame_texture.atlas = sheet
		frame_texture.region = Rect2(
			Vector2(column * SOLAR_CLEANING_FRAME_SIZE.x, row * SOLAR_CLEANING_FRAME_SIZE.y),
			Vector2(SOLAR_CLEANING_FRAME_SIZE.x, SOLAR_CLEANING_FRAME_SIZE.y)
		)
		frames.add_frame(&"clean_solar_panel", frame_texture)


func _physics_process(_delta: float) -> void:
	# --- Freeze check ---
	if not can_move:
		velocity = Vector2.ZERO
		move_and_slide()
		_update_walking_animation(Vector2.ZERO)
		AudioManager.set_footsteps(false)
		return

	if not _active_action_animation.is_empty():
		velocity = Vector2.ZERO
		move_and_slide()
		AudioManager.set_footsteps(false)
		return

	# --- Movement ---
	var direction := Input.get_vector(
		"move_left", "move_right",
		"move_up", "move_down"
	)
	velocity = direction * speed
	move_and_slide()

	_update_walking_animation(direction)
	# Footstep loop: only while actually walking.
	AudioManager.set_footsteps(direction.length() > 0.1)

	# --- Re-evaluate nearest target while moving ---
	# Only needed when multiple objects are in range.
	if _nearby_interactables.size() > 1:
		_update_interaction_target()


func _update_walking_animation(direction: Vector2) -> void:
	if not sprite or not sprite.sprite_frames or not _active_action_animation.is_empty():
		return

	if direction.is_zero_approx():
		if _last_facing_animation == &"walk_down":
			sprite.scale = IDLE_SOUTH_SCALE
			if sprite.animation != &"idle_down":
				sprite.play(&"idle_down")
			sprite.stop()
		elif sprite.is_playing():
			sprite.stop()
		return

	var animation_name := _animation_for_direction(direction)
	_last_facing_animation = animation_name
	sprite.scale = WALK_SCALES.get(animation_name, Vector2(0.25, 0.25))
	if sprite.animation != animation_name or not sprite.is_playing():
		sprite.play(animation_name)


func play_action_animation(animation_name: StringName, flip_h: bool = false) -> bool:
	if not sprite or not sprite.sprite_frames:
		return false
	if not ACTION_SCALES.has(animation_name) or not sprite.sprite_frames.has_animation(animation_name):
		return false
	if not _active_action_animation.is_empty():
		return false

	_active_action_animation = animation_name
	sprite.scale = ACTION_SCALES[animation_name]
	sprite.flip_h = flip_h
	sprite.play(animation_name)
	return true


func _on_sprite_animation_finished() -> void:
	if _active_action_animation.is_empty() or sprite.animation != _active_action_animation:
		return

	_active_action_animation = &""
	sprite.flip_h = false
	if _last_facing_animation == &"walk_down":
		sprite.scale = IDLE_SOUTH_SCALE
		sprite.play(&"idle_down")
		sprite.stop()
	else:
		sprite.scale = WALK_SCALES.get(_last_facing_animation, Vector2(0.25, 0.25))
		sprite.play(_last_facing_animation)
		sprite.stop()


func _animation_for_direction(direction: Vector2) -> StringName:
	var horizontal := "right" if direction.x > 0.0 else "left"
	var vertical := "down" if direction.y > 0.0 else "up"
	var abs_x := absf(direction.x)
	var abs_y := absf(direction.y)
	const DIAGONAL_THRESHOLD := 0.41421356

	if abs_x > abs_y * DIAGONAL_THRESHOLD and abs_y > abs_x * DIAGONAL_THRESHOLD:
		return StringName("walk_%s_%s" % [vertical, horizontal])
	if abs_y >= abs_x:
		return StringName("walk_%s" % vertical)
	return StringName("walk_%s" % horizontal)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		if not _active_action_animation.is_empty():
			get_viewport().set_input_as_handled()
			return
		if _current_target and is_instance_valid(_current_target):
			if _current_target.has_method("interact"):
				var interaction_target := _current_target
				interaction_target.interact(self)
				if _active_action_animation.is_empty():
					var flip_action_h := false
					if is_instance_valid(interaction_target) and interaction_target is Node2D:
						flip_action_h = (interaction_target as Node2D).global_position.x < global_position.x
					play_action_animation(&"interact_building", flip_action_h)
				get_viewport().set_input_as_handled()


# --- Interaction area callbacks ---

func _on_interaction_area_entered(area: Area2D) -> void:
	if area.is_in_group("interactable") and area not in _nearby_interactables:
		_nearby_interactables.append(area)
		_update_interaction_target()


func _on_interaction_area_exited(area: Area2D) -> void:
	_nearby_interactables.erase(area)
	# If the thing that left was our current target, clear it.
	if _current_target == area:
		if is_instance_valid(area) and area.has_method("hide_prompt"):
			area.hide_prompt()
		_current_target = null
	_update_interaction_target()


func _update_interaction_target() -> void:
	# Purge freed objects (e.g. a resource that was queue_free'd).
	_nearby_interactables = _nearby_interactables.filter(
		func(obj: Variant) -> bool: return is_instance_valid(obj)
	)

	if _nearby_interactables.is_empty():
		if _current_target and is_instance_valid(_current_target):
			if _current_target.has_method("hide_prompt"):
				_current_target.hide_prompt()
		_current_target = null
		return

	# Pick the closest one (distance² avoids a sqrt per frame).
	var nearest: Node = null
	var nearest_dist_sq: float = INF
	for obj: Node in _nearby_interactables:
		var d: float = global_position.distance_squared_to(obj.global_position)
		if d < nearest_dist_sq:
			nearest_dist_sq = d
			nearest = obj

	if nearest != _current_target:
		# Hide prompt on the old target.
		if _current_target and is_instance_valid(_current_target):
			if _current_target.has_method("hide_prompt"):
				_current_target.hide_prompt()
		# Show prompt on the new target.
		_current_target = nearest
		if _current_target and _current_target.has_method("show_prompt"):
			_current_target.show_prompt()

## True while the player stands next to something they can use.
## The HUD shows the painted "[E] TO INTERACT" prompt from this, so the prompt is
## driven by the same state the E key uses.
func has_interaction_target() -> bool:
	return _current_target != null and is_instance_valid(_current_target)


## The object E would act on right now (null when nothing is in reach).
func get_interaction_target() -> Node:
	return _current_target if has_interaction_target() else null
