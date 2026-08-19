extends Resource
class_name DamageAffinityDefinition

enum Response {
	NEUTRAL,
	WEAK,
	RESISTANT,
}

const WEAK_MULTIPLIER: float = 1.5
const RESISTANT_MULTIPLIER: float = 0.5

@export var damage_type: DamageTypeDefinition
@export var response: Response = Response.NEUTRAL

func validate(source: String) -> bool:
	if damage_type == null or not damage_type.validate(source):
		push_error("[DamageAffinityDefinition] Invalid damage type at %s" % source)
		return false
	if response not in [Response.WEAK, Response.RESISTANT]:
		push_error("[DamageAffinityDefinition] Neutral affinities should be omitted at %s" % source)
		return false
	return true

static func is_valid_response(value: int) -> bool:
	return value >= Response.NEUTRAL and value <= Response.RESISTANT

static func get_multiplier(value: int) -> float:
	assert(is_valid_response(value))
	match value:
		Response.WEAK:
			return WEAK_MULTIPLIER
		Response.RESISTANT:
			return RESISTANT_MULTIPLIER
		_:
			return 1.0
