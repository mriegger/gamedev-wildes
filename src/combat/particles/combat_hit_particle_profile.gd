extends Resource
class_name CombatHitParticleProfile

const PLAYER_DEFINITION_ID: StringName = &"player"

@export var source_definition_id: StringName
@export var target_definition_id: StringName
@export var primary_color: Color
@export var accent_color: Color

func validate(entity_catalog: EntityCatalog, source: String) -> bool:
	var valid := true
	if not _is_known_definition(source_definition_id, entity_catalog):
		push_error("[CombatHitParticleProfile] Unknown source %s at %s" % [source_definition_id, source])
		valid = false
	if not _is_known_definition(target_definition_id, entity_catalog):
		push_error("[CombatHitParticleProfile] Unknown target %s at %s" % [target_definition_id, source])
		valid = false
	if primary_color.a <= 0.0 or accent_color.a <= 0.0:
		push_error("[CombatHitParticleProfile] Transparent color at %s" % source)
		valid = false
	return valid

func _is_known_definition(definition_id: StringName, entity_catalog: EntityCatalog) -> bool:
	return definition_id == PLAYER_DEFINITION_ID or entity_catalog.has_definition(definition_id)
