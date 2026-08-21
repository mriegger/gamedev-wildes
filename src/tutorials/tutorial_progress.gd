extends RefCounted
class_name TutorialProgress

signal changed

var _mining_tip_completed: bool = false

func restore(snapshot: Variant) -> bool:
	if not snapshot is Dictionary:
		return false
	var data := snapshot as Dictionary
	if data.size() != 1 or not data.has("mining_tip_completed") or not data["mining_tip_completed"] is bool:
		return false
	_mining_tip_completed = bool(data["mining_tip_completed"])
	return true

func snapshot() -> Dictionary:
	return {"mining_tip_completed": _mining_tip_completed}

func is_mining_tip_completed() -> bool:
	return _mining_tip_completed

func complete_mining_tip() -> bool:
	if _mining_tip_completed:
		return false
	_mining_tip_completed = true
	changed.emit()
	return true
