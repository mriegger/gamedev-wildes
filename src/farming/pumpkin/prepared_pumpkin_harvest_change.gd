extends PreparedHarvestChange
class_name PreparedPumpkinHarvestChange

var _expected_state_id: StringName
var _result_state_id: StringName

func _init(
	p_owner: Object,
	p_expected_revision: int,
	p_tile_index: int,
	p_expected_state_id: StringName,
	p_result_state_id: StringName,
	p_harvest_item_ids: Array[StringName],
) -> void:
	super(p_owner, p_expected_revision, p_tile_index, p_harvest_item_ids)
	_expected_state_id = p_expected_state_id
	_result_state_id = p_result_state_id

func _get_expected_state_id() -> StringName:
	return _expected_state_id

func _get_result_state_id() -> StringName:
	return _result_state_id
