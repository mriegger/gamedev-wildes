extends Resource
class_name CombatHitParticleCatalog

@export var profiles: Array[CombatHitParticleProfile]:
	set(value):
		profiles = value
		_rebuild_lookup()

var _profiles_by_source: Dictionary = {}

func validate(entity_catalog: EntityCatalog) -> bool:
	_rebuild_lookup()
	var valid := true
	var seen_pairs: Dictionary = {}
	for profile in profiles:
		if profile == null:
			push_error("[CombatHitParticleCatalog] Null profile")
			valid = false
			continue
		var source := profile.resource_path
		if not profile.validate(entity_catalog, source):
			valid = false
		var seen_targets := seen_pairs.get(profile.source_definition_id, {}) as Dictionary
		if seen_targets.has(profile.target_definition_id):
			push_error("[CombatHitParticleCatalog] Duplicate contact pair at %s" % source)
			valid = false
		else:
			seen_targets[profile.target_definition_id] = true
			seen_pairs[profile.source_definition_id] = seen_targets
	return valid

func get_profile(source_definition_id: StringName, target_definition_id: StringName) -> CombatHitParticleProfile:
	var targets := _profiles_by_source.get(source_definition_id, {}) as Dictionary
	return targets.get(target_definition_id) as CombatHitParticleProfile

func _rebuild_lookup():
	_profiles_by_source.clear()
	for profile in profiles:
		if profile == null:
			continue
		var targets := _profiles_by_source.get(profile.source_definition_id, {}) as Dictionary
		targets[profile.target_definition_id] = profile
		_profiles_by_source[profile.source_definition_id] = targets
