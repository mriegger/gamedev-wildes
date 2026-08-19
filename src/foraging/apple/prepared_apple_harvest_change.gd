extends PreparedHarvestChange
class_name PreparedAppleHarvestChange

var _tree_position: Vector3i
var _slot_index: int
var _decorative_index: int

func _init(
	p_owner: Object,
	p_expected_revision: int,
	p_target_id: int,
	p_tree_position: Vector3i,
	p_slot_index: int,
	p_decorative_index: int,
	p_harvest_item_ids: Array[StringName],
) -> void:
	super(p_owner, p_expected_revision, p_target_id, p_harvest_item_ids)
	_tree_position = p_tree_position
	_slot_index = p_slot_index
	_decorative_index = p_decorative_index

func _get_tree_position() -> Vector3i:
	return _tree_position

func _get_slot_index() -> int:
	return _slot_index

func _get_decorative_index() -> int:
	return _decorative_index
