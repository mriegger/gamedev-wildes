extends RefCounted
class_name TutorialProgress

signal changed

var _mining_tip_completed: bool = false
var _food_tip_completed: bool = false
var _crafting_tip_completed: bool = false
var _crafting_ingredients_tip_completed: bool = false

func restore(snapshot: Variant) -> bool:
	if not snapshot is Dictionary:
		return false
	var data := snapshot as Dictionary
	if (
		data.size() != 4
		or not data.has("mining_tip_completed")
		or not data["mining_tip_completed"] is bool
		or not data.has("food_tip_completed")
		or not data["food_tip_completed"] is bool
		or not data.has("crafting_tip_completed")
		or not data["crafting_tip_completed"] is bool
		or not data.has("crafting_ingredients_tip_completed")
		or not data["crafting_ingredients_tip_completed"] is bool
	):
		return false
	_mining_tip_completed = bool(data["mining_tip_completed"])
	_food_tip_completed = bool(data["food_tip_completed"])
	_crafting_tip_completed = bool(data["crafting_tip_completed"])
	_crafting_ingredients_tip_completed = bool(data["crafting_ingredients_tip_completed"])
	return true

func snapshot() -> Dictionary:
	return {
		"mining_tip_completed": _mining_tip_completed,
		"food_tip_completed": _food_tip_completed,
		"crafting_tip_completed": _crafting_tip_completed,
		"crafting_ingredients_tip_completed": _crafting_ingredients_tip_completed,
	}

func is_mining_tip_completed() -> bool:
	return _mining_tip_completed

func complete_mining_tip() -> bool:
	if _mining_tip_completed:
		return false
	_mining_tip_completed = true
	changed.emit()
	return true

func is_food_tip_completed() -> bool:
	return _food_tip_completed

func complete_food_tip() -> bool:
	if _food_tip_completed:
		return false
	_food_tip_completed = true
	changed.emit()
	return true

func is_crafting_tip_completed() -> bool:
	return _crafting_tip_completed

func complete_crafting_tip() -> bool:
	if _crafting_tip_completed:
		return false
	_crafting_tip_completed = true
	changed.emit()
	return true

func is_crafting_ingredients_tip_completed() -> bool:
	return _crafting_ingredients_tip_completed

func complete_crafting_ingredients_tip() -> bool:
	if _crafting_ingredients_tip_completed:
		return false
	_crafting_ingredients_tip_completed = true
	changed.emit()
	return true
