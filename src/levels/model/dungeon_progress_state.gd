extends RefCounted
class_name DungeonProgressState

signal state_changed

const SNAPSHOT_VERSION: int = 1
const MAXIMUM_COUNTER_VALUE: int = 2147483646

var _instances: Dictionary = {}
var _revision: int = 0

func begin_attempt(instance_id: StringName) -> int:
	if instance_id.is_empty():
		return -1
	var record := _get_record(instance_id)
	var attempt_index := int(record["next_attempt_index"])
	if attempt_index >= MAXIMUM_COUNTER_VALUE:
		return -1
	record["next_attempt_index"] = attempt_index + 1
	_instances[instance_id] = record
	_revision += 1
	state_changed.emit()
	return attempt_index

func get_completion_count(instance_id: StringName) -> int:
	if instance_id.is_empty() or not _instances.has(instance_id):
		return 0
	return int((_instances[instance_id] as Dictionary)["completion_count"])

func has_claimed_reward(instance_id: StringName, reward_id: StringName) -> bool:
	if instance_id.is_empty() or reward_id.is_empty() or not _instances.has(instance_id):
		return false
	var claimed_reward_ids := (_instances[instance_id] as Dictionary)["claimed_reward_ids"] as Dictionary
	return claimed_reward_ids.has(reward_id)

func prepare_reward_claim(
	instance_id: StringName,
	reward_id: StringName,
) -> PreparedDungeonRewardClaim:
	if instance_id.is_empty() or reward_id.is_empty() or has_claimed_reward(instance_id, reward_id):
		return null
	return PreparedDungeonRewardClaim.new(
		self,
		_revision,
		instance_id,
		reward_id,
	)

func can_commit_prepared_reward_claim(prepared: PreparedDungeonRewardClaim) -> bool:
	if (
		prepared == null
		or not prepared._is_for(self)
		or not prepared._is_prepared()
		or prepared._get_expected_revision() != _revision
	):
		return false
	var instance_id := prepared._get_instance_id()
	var reward_id := prepared._get_reward_id()
	return (
		not instance_id.is_empty()
		and not reward_id.is_empty()
		and not has_claimed_reward(instance_id, reward_id)
	)

func commit_prepared_reward_claim(prepared: PreparedDungeonRewardClaim) -> bool:
	if not _commit_prepared_reward_claim(prepared):
		return false
	var notified := _notify_prepared_reward_claim(prepared)
	assert(notified)
	return notified

func _commit_prepared_reward_claim(prepared: PreparedDungeonRewardClaim) -> bool:
	if not can_commit_prepared_reward_claim(prepared):
		return false
	var instance_id := prepared._get_instance_id()
	var record := _get_record(instance_id)
	var claimed_reward_ids := record["claimed_reward_ids"] as Dictionary
	claimed_reward_ids[prepared._get_reward_id()] = true
	_instances[instance_id] = record
	_revision += 1
	var marked := prepared._mark_committed(self)
	assert(marked)
	return marked

func _notify_prepared_reward_claim(prepared: PreparedDungeonRewardClaim) -> bool:
	if prepared == null or not prepared._mark_notified(self):
		return false
	state_changed.emit()
	return true

func prepare_completion(instance_id: StringName) -> PreparedDungeonCompletionChange:
	if instance_id.is_empty():
		return null
	var completion_count := get_completion_count(instance_id)
	if completion_count >= MAXIMUM_COUNTER_VALUE:
		return null
	return PreparedDungeonCompletionChange.new(
		self,
		_revision,
		instance_id,
		completion_count,
		completion_count + 1,
	)

func can_commit_prepared_completion(prepared: PreparedDungeonCompletionChange) -> bool:
	if (
		prepared == null
		or not prepared._is_for(self)
		or not prepared._is_prepared()
		or prepared._get_expected_revision() != _revision
	):
		return false
	var instance_id := prepared._get_instance_id()
	var expected_count := prepared._get_expected_completion_count()
	return (
		not instance_id.is_empty()
		and expected_count >= 0
		and expected_count < MAXIMUM_COUNTER_VALUE
		and get_completion_count(instance_id) == expected_count
		and prepared._get_result_completion_count() == expected_count + 1
	)

func commit_prepared_completion(prepared: PreparedDungeonCompletionChange) -> bool:
	if not _commit_prepared_completion(prepared):
		return false
	var notified := _notify_prepared_completion(prepared)
	assert(notified)
	return notified

func _commit_prepared_completion(prepared: PreparedDungeonCompletionChange) -> bool:
	if not can_commit_prepared_completion(prepared):
		return false
	var instance_id := prepared._get_instance_id()
	var record := _get_record(instance_id)
	record["completion_count"] = prepared._get_result_completion_count()
	_instances[instance_id] = record
	_revision += 1
	var marked := prepared._mark_committed(self)
	assert(marked)
	return marked

func _notify_prepared_completion(prepared: PreparedDungeonCompletionChange) -> bool:
	if prepared == null or not prepared._mark_notified(self):
		return false
	state_changed.emit()
	return true

func snapshot() -> Dictionary:
	var encoded_instances: Dictionary = {}
	var encoded_instance_ids: Array[String] = []
	for instance_id in _instances:
		encoded_instance_ids.append(String(instance_id))
	encoded_instance_ids.sort()
	for encoded_instance_id in encoded_instance_ids:
		var instance_id := StringName(encoded_instance_id)
		var record := _instances[instance_id] as Dictionary
		var encoded_reward_ids: Array[String] = []
		for reward_id in record["claimed_reward_ids"]:
			encoded_reward_ids.append(String(reward_id))
		encoded_reward_ids.sort()
		encoded_instances[encoded_instance_id] = {
			"next_attempt_index": int(record["next_attempt_index"]),
			"completion_count": int(record["completion_count"]),
			"claimed_reward_ids": encoded_reward_ids,
		}
	return {
		"version": SNAPSHOT_VERSION,
		"instances": encoded_instances,
	}

func restore(encoded: Variant) -> bool:
	if not encoded is Dictionary or encoded.size() != 2:
		return false
	if not encoded.has("version") or not encoded.has("instances"):
		return false
	var version := _decode_counter(encoded["version"])
	if version != SNAPSHOT_VERSION:
		return false
	var raw_instances = encoded["instances"]
	if not raw_instances is Dictionary:
		return false
	var decoded_instances: Dictionary = {}
	for raw_instance_id in raw_instances:
		if not raw_instance_id is String or raw_instance_id.is_empty():
			return false
		var instance_id := StringName(raw_instance_id)
		if decoded_instances.has(instance_id):
			return false
		var raw_record = raw_instances[raw_instance_id]
		if not raw_record is Dictionary or raw_record.size() != 3:
			return false
		if (
			not raw_record.has("next_attempt_index")
			or not raw_record.has("completion_count")
			or not raw_record.has("claimed_reward_ids")
		):
			return false
		var next_attempt_index := _decode_counter(raw_record["next_attempt_index"])
		var completion_count := _decode_counter(raw_record["completion_count"])
		if next_attempt_index < 0 or completion_count < 0:
			return false
		var raw_reward_ids = raw_record["claimed_reward_ids"]
		if not raw_reward_ids is Array:
			return false
		var claimed_reward_ids: Dictionary = {}
		for raw_reward_id in raw_reward_ids:
			if not raw_reward_id is String or raw_reward_id.is_empty():
				return false
			var reward_id := StringName(raw_reward_id)
			if claimed_reward_ids.has(reward_id):
				return false
			claimed_reward_ids[reward_id] = true
		decoded_instances[instance_id] = {
			"next_attempt_index": next_attempt_index,
			"completion_count": completion_count,
			"claimed_reward_ids": claimed_reward_ids,
		}
	_instances = decoded_instances
	_revision += 1
	return true

func _get_record(instance_id: StringName) -> Dictionary:
	if _instances.has(instance_id):
		var existing := _instances[instance_id] as Dictionary
		return {
			"next_attempt_index": int(existing["next_attempt_index"]),
			"completion_count": int(existing["completion_count"]),
			"claimed_reward_ids": (existing["claimed_reward_ids"] as Dictionary).duplicate(),
		}
	return {
		"next_attempt_index": 0,
		"completion_count": 0,
		"claimed_reward_ids": {},
	}

static func _decode_counter(raw_value: Variant) -> int:
	if typeof(raw_value) != TYPE_INT and typeof(raw_value) != TYPE_FLOAT:
		return -1
	var numeric_value := float(raw_value)
	if not is_finite(numeric_value) or numeric_value < 0.0 or numeric_value > MAXIMUM_COUNTER_VALUE:
		return -1
	var value := int(raw_value)
	return value if numeric_value == float(value) else -1
