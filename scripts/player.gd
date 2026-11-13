## scripts/player.gd
## Player controller: 8-direction top-down movement with camera follow.
## Uses Input.get_vector which automatically normalizes diagonals,
## so diagonal speed equals straight-line speed.
extends CharacterBody2D

## Movement speed in pixels per second. Tweak in the Inspector.
@export var speed: float = 200.0

## Set to false to freeze the player (e.g. when a menu is open).
## Other scripts can do: player.can_move = false
@export var can_move: bool = true

## Camera limits — set these to match the map edges so the camera
## never shows empty space outside the playable area.
@export_group("Camera Limits")
@export var camera_limit_left: int = 0
@export var camera_limit_top: int = 0
@export var camera_limit_right: int = 2000
@export var camera_limit_bottom: int = 1200

# Node references — resolved once when the scene loads.
@onready var sprite: Sprite2D = $Sprite2D
@onready var camera: Camera2D = $Camera2D


func _ready() -> void:
	# Apply the exported camera limits to the actual Camera2D node.
	if camera:
		camera.limit_left = camera_limit_left
		camera.limit_top = camera_limit_top
		camera.limit_right = camera_limit_right
		camera.limit_bottom = camera_limit_bottom


func _physics_process(_delta: float) -> void:
	# --- Freeze check ---
	if not can_move:
		# Stop all movement immediately so the player doesn't drift.
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# --- Read input ---
	# get_vector returns a Vector2 clamped to length 1.0.
	# When two axes are pressed (diagonal), the vector is normalized,
	# so the player moves at the same speed in every direction.
	var direction := Input.get_vector(
		"move_left", "move_right",
		"move_up", "move_down"
	)

	# --- Apply movement ---
	velocity = direction * speed
	move_and_slide()

	# --- Flip sprite ---
	# Only change flip when the player is actually moving horizontally,
	# so the sprite keeps its last facing when the player stops.
	if sprite:
		if direction.x > 0.0:
			sprite.flip_h = false
		elif direction.x < 0.0:
			sprite.flip_h = true
