## scripts/decor_spawner.gd
## Uses the loose sprites the pack delivered (78 rocks, 73 craters, 78 ore chunks in
## assets/sprites/environment/*_v2/) to break up the empty ground.
##
## Placement is deterministic: same seed -> same map, so screenshots and testing stay
## comparable.  Everything here is decorative (no collision) and keeps clear of the
## starting base and the buildings the scene already places.
##
## SIZES ARE IN WORLD PIXELS, NOT RAW ART SCALE.  The pack sprites were drawn on large
## canvases (33x32 up to 117x109 px of content), so scaling each texture by
## desired_pixels / texture_size keeps every rock smaller than the astronaut, who is
## roughly 28x44 px on screen.
extends Node2D

## Changing the seed re-skins the whole terrain layout.
@export var seed_value: int = 20261113
@export var enable_craters: bool = true
@export var enable_rocks: bool = true
@export var enable_ore: bool = true

const FOLDER := "res://assets/sprites/environment/"

## dir, how many files exist, how many to place, z-index, world-pixel size range
const SETS := {
	"craters": {
		"dir": "craters_v2/crater_", "count": 73, "place": 16,
		"z": -1, "min_px": 64.0, "max_px": 118.0,
	},
	"rocks": {
		"dir": "rocks_v2/rock_", "count": 78, "place": 24,
		"z": 1, "min_px": 24.0, "max_px": 44.0,
	},
	"ore": {
		"dir": "ore_v2/ore_", "count": 78, "place": 9,
		"z": 1, "min_px": 15.0, "max_px": 28.0,
	},
}

## Where the scene already has buildings / farms / the player start.
const KEEP_OUT: Array[Rect2] = [
	Rect2(300, 250, 680, 380),     # habitat, storage, water works, research row
	Rect2(1000, 540, 300, 300),    # farm plots
	Rect2(840, 500, 340, 240),     # player spawn area
	Rect2(640, 500, 300, 420),     # the pre-placed solar / oxygen / greenhouse block
	Rect2(1400, 300, 420, 700),    # right-hand painted slots and props
]

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = seed_value
	for key: String in SETS:
		if not _enabled_for(key):
			continue
		_scatter(key, SETS[key])


func _enabled_for(key: String) -> bool:
	match key:
		"craters":
			return enable_craters
		"rocks":
			return enable_rocks
		"ore":
			return enable_ore
	return false


## Places `spec["place"]` sprites of a set at deterministic random spots.
func _scatter(key: String, spec: Dictionary) -> void:
	var placed := 0
	var attempts := 0
	var limit := int(spec["place"]) * 14
	while placed < int(spec["place"]) and attempts < limit:
		attempts += 1
		var spot := Vector2(
			_rng.randf_range(80.0, 1920.0),
			_rng.randf_range(80.0, 1120.0)
		)
		if _is_keep_out(spot):
			continue
		var index := _rng.randi_range(1, int(spec["count"]))
		var path: String = "%s%s%02d.png" % [FOLDER, spec["dir"], index]
		var texture := load(path) as Texture2D
		if texture == null:
			continue

		# Normalise: the wanted world size divided by the sprite's own pixel size.
		var longest := maxf(float(texture.get_width()), float(texture.get_height()))
		var want: float = _rng.randf_range(float(spec["min_px"]), float(spec["max_px"]))
		var scale_v: float = want / maxf(longest, 1.0)

		var sprite := Sprite2D.new()
		sprite.name = "Decor_%s_%02d" % [key, placed + 1]
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.position = spot
		sprite.scale = Vector2(scale_v, scale_v)
		sprite.rotation_degrees = 0.0 if key == "craters" else _rng.randf_range(0.0, 360.0)
		# Craters read as ground stains, so keep them slightly translucent.
		sprite.modulate = Color(1, 1, 1, 0.8) if key == "craters" else Color(1, 1, 1, 0.95)
		sprite.z_index = int(spec["z"])
		add_child(sprite)
		placed += 1


func _is_keep_out(point: Vector2) -> bool:
	for rect: Rect2 in KEEP_OUT:
		if rect.grow(30.0).has_point(point):
			return true
	return false
