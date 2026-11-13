## scripts/resource_manager.gd
## FAKE placeholder — will be replaced by the Backend Lead's real version.
## Provides the exact contract API so every other script can develop against it.
## All resource values are integers (no decimals — kids see whole numbers).
extends Node

# Emitted whenever any resource total changes.
# 'type' is one of: "ore", "water", "oxygen", "energy", "food", "shield", "science"
# 'new_total' is the value AFTER the change.
@warning_ignore("unused_signal")
signal resource_changed(type: String, new_total: int)

# Starting amounts — tunable, will move to a JSON later.
var _resources: Dictionary = {
	"ore":     0,
	"water":   20,
	"oxygen":  100,
	"energy":  50,
	"food":    20,
	"shield":  0,
	"science": 0,
}


func _ready() -> void:
	# Emit initial values so the HUD can pick them up at startup.
	for type: String in _resources:
		resource_changed.emit(type, _resources[type])


## Add a positive amount of a resource. Negative amounts are ignored.
func add(type: String, amount: int) -> void:
	if not _resources.has(type):
		push_warning("ResourceManager.add(): unknown type '%s'" % type)
		return
	if amount <= 0:
		return
	_resources[type] += amount
	resource_changed.emit(type, _resources[type])


## Return the current amount, or 0 if the type is unknown.
func get_amount(type: String) -> int:
	if not _resources.has(type):
		push_warning("ResourceManager.get_amount(): unknown type '%s'" % type)
		return 0
	return _resources[type]


## Check whether we can afford a cost dictionary like {"ore": 5, "energy": 10}.
## Returns true only if EVERY resource in the cost is available.
func has_enough(cost: Dictionary) -> bool:
	for type: String in cost:
		if not _resources.has(type):
			push_warning("ResourceManager.has_enough(): unknown type '%s'" % type)
			return false
		if _resources[type] < int(cost[type]):
			return false
	return true


## Spend resources atomically: if we can afford the whole cost, subtract
## everything and return true. If we cannot, change NOTHING and return false.
func spend(cost: Dictionary) -> bool:
	if not has_enough(cost):
		return false
	for type: String in cost:
		_resources[type] -= int(cost[type])
		resource_changed.emit(type, _resources[type])
	return true


## Debug helper: returns a copy of all resources (safe to print).
func get_all() -> Dictionary:
	return _resources.duplicate()
