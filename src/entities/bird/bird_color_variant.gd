extends RefCounted
class_name BirdColorVariant

enum Type {
	CROW,
	REDBIRD,
	DUCK,
	BLUEBIRD,
	OWL,
}

const COMMON_COUNT: int = Type.BLUEBIRD + 1
const COUNT: int = Type.OWL + 1

static func common_for_seed(seed_value: int) -> Type:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0x4b1d5eed
	return rng.randi_range(Type.CROW, Type.BLUEBIRD) as Type

static func index_for_id(variant_id: StringName) -> int:
	match variant_id:
		&"crow":
			return Type.CROW
		&"redbird":
			return Type.REDBIRD
		&"duck":
			return Type.DUCK
		&"bluebird":
			return Type.BLUEBIRD
		&"owl":
			return Type.OWL
	return -1

static func behavior_seed_for_common_variant(variant_index: int, seed_start: int) -> int:
	assert(variant_index >= Type.CROW and variant_index <= Type.BLUEBIRD)
	var variant := variant_index as Type
	var candidate := seed_start
	for _attempt in 256:
		if common_for_seed(candidate) == variant:
			return candidate
		candidate += 1
	assert(false)
	return seed_start
