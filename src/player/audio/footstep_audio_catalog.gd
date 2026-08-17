extends Resource
class_name FootstepAudioCatalog

@export var fallback_profile: FootstepAudioProfile:
	set(value):
		fallback_profile = value
		_rebuild_lookup()
@export var profiles: Array[FootstepAudioProfile] = []:
	set(value):
		profiles = value
		_rebuild_lookup()

var _profiles_by_block: Array[FootstepAudioProfile] = []
var _is_valid: bool = false


func _rebuild_lookup():
	_profiles_by_block.clear()
	_profiles_by_block.resize(BlockId.Type.COUNT)
	_is_valid = fallback_profile != null and fallback_profile.validate()
	for profile in profiles:
		if profile == null or not profile.validate():
			_is_valid = false
			continue
		var block_id := int(profile.surface_block_id)
		if _profiles_by_block[block_id] != null:
			_is_valid = false
			continue
		_profiles_by_block[block_id] = profile


func _ensure_lookup():
	if _profiles_by_block.size() != BlockId.Type.COUNT:
		_rebuild_lookup()


func validate() -> bool:
	_ensure_lookup()
	return _is_valid


func get_profile(block_id: int) -> FootstepAudioProfile:
	_ensure_lookup()
	assert(BlockId.is_valid(block_id))
	var profile := _profiles_by_block[block_id]
	return profile if profile != null else fallback_profile
