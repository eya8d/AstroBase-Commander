## scripts/main_debug.gd
## Temporary debug script for the main scene.
## Shows all resource values on screen and lets us test the ResourceManager.
## DELETE THIS once the real HUD is connected.
extends Node2D

# DebugLabel is now under a CanvasLayer so it stays fixed on screen
# even when the camera follows the player around the map.
@onready var debug_label: Label = $UILayer/DebugLabel


func _ready() -> void:
	# Listen for any resource change so we can refresh the display.
	ResourceManager.resource_changed.connect(_on_resource_changed)
	_refresh_label()

	# Also verify DataLoader works by loading buildings.
	var buildings: Array = DataLoader.get_buildings()
	print("DataLoader test: loaded %d buildings." % buildings.size())


func _unhandled_input(event: InputEvent) -> void:
	# Press O = add 5 ore (debug test).
	# We check the raw keycode so this works even without an Input Map entry.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_O:
			ResourceManager.add("ore", 5)
			print("DEBUG: added 5 ore → total = %d" % ResourceManager.get_amount("ore"))

			# Also test spend() with too little shield.
			var result: bool = ResourceManager.spend({"shield": 999})
			print("DEBUG: spend 999 shield = %s (should be false)" % result)


func _on_resource_changed(_type: String, _new_total: int) -> void:
	_refresh_label()


func _refresh_label() -> void:
	if not is_instance_valid(debug_label):
		return
	var all: Dictionary = ResourceManager.get_all()
	var lines: PackedStringArray = PackedStringArray()
	lines.append("=== MARS SURVIVAL ACADEMY ===")
	lines.append("(Debug View — Section 0)")
	lines.append("")
	for key: String in all:
		lines.append("  %s: %d" % [key.to_upper(), all[key]])
	lines.append("")
	lines.append("Press O to add 5 ore | WASD to move")
	debug_label.text = "\n".join(lines)
