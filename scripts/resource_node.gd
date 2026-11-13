## scripts/resource_node.gd
## A collectible resource in the world (ore rock, water ice, etc.).
## REFACTORED for Section 3: uses the unified interaction system.
## The PLAYER now handles proximity detection and E-key input.
## This script just exposes interact(), show_prompt(), hide_prompt().
extends Area2D

@export var resource_type: String = "ore"
@export var amount_per_collect: int = 1
@export var total_amount: int = 5
@export var sprite_color: Color = Color(0.7, 0.7, 0.7, 1.0)

@export_group("Respawn")
## Seconds before the resource reappears after depletion. 0 = never.
@export var respawn_time: float = 15.0
## If true, the resource reappears at a random spot inside the spawn area.
@export var respawn_random_position: bool = true
## Top-left corner of the area where the resource can respawn.
@export var spawn_area_min: Vector2 = Vector2(50, 50)
## Bottom-right corner of the area where the resource can respawn.
@export var spawn_area_max: Vector2 = Vector2(1950, 1150)

var _depleted: bool = false
var _remaining: int = 0

@onready var sprite: Sprite2D = $Sprite2D
@onready var prompt_label: Label = $PromptLabel
@onready var type_label: Label = $TypeLabel
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	_remaining = total_amount
	prompt_label.visible = false
	add_to_group("interactable")

	if sprite:
		sprite.modulate = sprite_color

	# Set the label text from resource_type (e.g. "ORE", "WATER").
	# Starts HIDDEN — only shown when the player approaches (show_prompt).
	if type_label:
		type_label.text = resource_type.to_upper()
		type_label.visible = false


# --- Unified interaction interface (called by the player) ---

func interact(player: Node) -> void:
	if _depleted:
		return
	_collect(player)


func show_prompt() -> void:
	if not _depleted:
		prompt_label.visible = true
		if type_label:
			type_label.visible = true


func hide_prompt() -> void:
	prompt_label.visible = false
	if type_label:
		type_label.visible = false


# --- Internal ---

func _collect(player: Node) -> void:
	var to_add: int = mini(amount_per_collect, _remaining)
	if to_add <= 0:
		return

	var action_animation: StringName = &""
	if resource_type == "water":
		action_animation = &"collect_water"
	elif resource_type == "ore":
		action_animation = &"mine_hammer"
	if action_animation != &"" and is_instance_valid(player) and player is Node2D:
		var actor := player as Node2D
		if actor.has_method("play_action_animation"):
			var face_left := action_animation == &"collect_water" and global_position.x < actor.global_position.x
			actor.call("play_action_animation", action_animation, face_left)

	_remaining -= to_add
	ResourceManager.add(resource_type, to_add)
	EventBus.item_collected.emit(resource_type, to_add)

	# Juice: tiny "pop" scale animation.
	if sprite:
		var tween := create_tween()
		tween.tween_property(sprite, "scale", Vector2(1.3, 1.3), 0.08)
		tween.tween_property(sprite, "scale", Vector2(1.0, 1.0), 0.08)

	if _remaining <= 0:
		_deplete()


func _deplete() -> void:
	_depleted = true
	prompt_label.visible = false
	if type_label:
		type_label.visible = false
	visible = false
	collision_shape.set_deferred("disabled", true)

	if respawn_time > 0.0:
		get_tree().create_timer(respawn_time).timeout.connect(_respawn)


func _respawn() -> void:
	if not is_inside_tree():
		return
	_remaining = total_amount
	_depleted = false
	# Move to a random position inside the spawn area if enabled.
	if respawn_random_position:
		position = Vector2(
			randf_range(spawn_area_min.x, spawn_area_max.x),
			randf_range(spawn_area_min.y, spawn_area_max.y)
		)
	visible = true
	collision_shape.set_deferred("disabled", false)
