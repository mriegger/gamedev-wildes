extends RefCounted
class_name FoliageGenerator

const HASH_MASK: int = 0xffffffff
const HASH_RANGE: float = 4294967296.0
const X_PRIME: int = 73856093
const Z_PRIME: int = 19349663
const MIX_PRIME: int = 1274126177
const OCCUPANCY_SALT: int = 1374496523
const SPECIES_SALT: int = 1757159915
const PATCH_SALT: int = 1013904223
const PATCH_SIZE: int = 8
const PATCH_MIN_FACTOR: float = 0.2
const PATCH_MAX_FACTOR: float = 1.8

var _block_ids := PackedInt32Array()
var _cumulative_weights := PackedInt32Array()
var _total_generation_weight: int
var _seed_value: int

func _init(catalog: FoliageCatalog, seed_value: int) -> void:
	assert(catalog != null)
	_seed_value = seed_value
	for definition in catalog.species:
		_total_generation_weight += definition.generation_weight
		_block_ids.append(definition.block.id)
		_cumulative_weights.append(_total_generation_weight)
	assert(_total_generation_weight > 0)

func select_block_id(world_x: int, world_z: int, foliage_density: float) -> int:
	assert(foliage_density >= 0.0 and foliage_density <= 1.0)
	if foliage_density <= 0.0:
		return BlockId.Type.AIR
	var occupancy := float(_coordinate_hash(world_x, world_z, OCCUPANCY_SALT)) / HASH_RANGE
	var local_density := 1.0 if foliage_density >= 1.0 else foliage_density * _patch_factor(world_x, world_z)
	if occupancy >= local_density:
		return BlockId.Type.AIR
	var species_roll := _coordinate_hash(world_x, world_z, SPECIES_SALT) % _total_generation_weight
	for index in _cumulative_weights.size():
		if species_roll < _cumulative_weights[index]:
			return _block_ids[index]
	assert(false)
	return BlockId.Type.AIR

func _patch_factor(world_x: int, world_z: int) -> float:
	var patch_x := floori(float(world_x) / float(PATCH_SIZE))
	var patch_z := floori(float(world_z) / float(PATCH_SIZE))
	var local_x := float(world_x - patch_x * PATCH_SIZE) / float(PATCH_SIZE)
	var local_z := float(world_z - patch_z * PATCH_SIZE) / float(PATCH_SIZE)
	var blend_x := local_x * local_x * (3.0 - 2.0 * local_x)
	var blend_z := local_z * local_z * (3.0 - 2.0 * local_z)
	var north_west := float(_coordinate_hash(patch_x, patch_z, PATCH_SALT)) / HASH_RANGE
	var north_east := float(_coordinate_hash(patch_x + 1, patch_z, PATCH_SALT)) / HASH_RANGE
	var south_west := float(_coordinate_hash(patch_x, patch_z + 1, PATCH_SALT)) / HASH_RANGE
	var south_east := float(_coordinate_hash(patch_x + 1, patch_z + 1, PATCH_SALT)) / HASH_RANGE
	var north := lerpf(north_west, north_east, blend_x)
	var south := lerpf(south_west, south_east, blend_x)
	return lerpf(PATCH_MIN_FACTOR, PATCH_MAX_FACTOR, lerpf(north, south, blend_z))

func _coordinate_hash(world_x: int, world_z: int, salt: int) -> int:
	var value := int(_seed_value & HASH_MASK)
	value = int((value ^ ((world_x * X_PRIME) & HASH_MASK) ^ ((world_z * Z_PRIME) & HASH_MASK) ^ salt) & HASH_MASK)
	value = int((value ^ (value >> 13)) & HASH_MASK)
	value = int((value * MIX_PRIME) & HASH_MASK)
	value = int((value ^ (value >> 16)) & HASH_MASK)
	return value
