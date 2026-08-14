extends Resource
class_name WorldConfig

@export_group("Dimensions")
@export var seed_value: int = 1337
@export var chunk_size: int = 20
@export var max_height: int = 20
@export var build_extra: int = 8
@export var water_level: int = 5

var max_build_y: int:
	get:
		return max_height + build_extra + 8

@export_group("Biomes & Terrain")
@export var meadow_radius: float = 22.0
@export var meadow_target_height: float = 9.5
@export var base_height: float = 8.5

@export_group("Vegetation")
@export var tree_density: float = 0.01
@export var tree_trunk_min: int = 3
@export var tree_trunk_max: int = 4
@export var tree_spacing: float = 4.5

@export_group("Copper Deposits")
@export var copper_deposits_enabled: bool = true
@export_range(0.0, 1.0) var copper_deposit_chance_per_chunk: float = 0.22
@export_range(1, 100) var copper_deposit_min_blocks: int = 5
@export_range(1, 100) var copper_deposit_max_blocks: int = 30
@export_range(0.0, 1.0) var copper_surface_exposure_chance: float = 0.55
@export_range(0, 10) var copper_max_surface_blocks: int = 3

@export_group("Noise - Continentalness")
@export var continentalness_frequency: float = 0.0018
@export var continentalness_octaves: int = 4
@export var continentalness_seed_offset: int = 11

@export_group("Noise - Erosion")
@export var erosion_frequency: float = 0.0045
@export var erosion_octaves: int = 3
@export var erosion_seed_offset: int = 23

@export_group("Noise - PeaksValleys")
@export var peaks_valleys_frequency: float = 0.018
@export var peaks_valleys_octaves: int = 2
@export var peaks_valleys_seed_offset: int = 37

@export_group("Noise - Temperature")
@export var temperature_frequency: float = 0.0048
@export var temperature_octaves: int = 3
@export var temperature_seed_offset: int = 51

@export_group("Noise - Humidity")
@export var humidity_frequency: float = 0.0048
@export var humidity_octaves: int = 3
@export var humidity_seed_offset: int = 67

@export_group("Splines")
# Continentalness 0..1 -> elevation offset (blocks). Piecewise linear.
@export var continentalness_curve: PackedVector2Array = PackedVector2Array([
	Vector2(0.0, -4.0), Vector2(0.25, -1.0), Vector2(0.5, 2.0), Vector2(0.75, 5.2), Vector2(1.0, 9.0)
])
# Erosion 0..1 -> amplitude multiplier 0..1. High erosion = flat.
@export var erosion_amplitude_curve: PackedVector2Array = PackedVector2Array([
	Vector2(0.0, 1.0), Vector2(0.3, 0.82), Vector2(0.6, 0.38), Vector2(1.0, 0.1)
])
# Relief scale: how much peaks_valleys * amplitude contributes to height.
@export var relief_scale: float = 9.0
# PeaksValleys scaling is via amplitude * pv; no extra curve needed.

@export_group("Generation")
@export_range(1, 8) var param_lattice_step: int = 4

@export_group("Shore")
@export var shore_influence_min: float = 0.12
@export var shore_influence_strong: float = 0.25
@export var shore_height_margin: int = 3
@export var shore_waterline_margin: int = 1

@export_group("Biomes")
@export var biome_library: BiomeLibrary

@export_group("Lakes")
@export var lake_enabled: bool = true
@export var lake_radius_min: int = 16
@export var lake_radius_max: int = 42
@export var lake_depth: int = 6
@export var lake_min_dist_from_meadow: float = 28.0
@export var lake_grid_size: int = 180
@export var lake_chance_per_cell: float = 0.68
@export var lake_rim_blend: float = 0.80

@export_group("Rivers")
@export var river_enabled: bool = true
@export var river_depth: int = 3
@export var river_min_dist_from_meadow: float = 22.0
@export var river_frequency: float = 0.006
@export var river_seed_offset: int = 505

@export_group("Lighting / Rendering")
@export var enable_ao: bool = true

@export_group("Chunk Streaming")
@export var render_distance: int = 4
@export var unload_padding: int = 2
@export var max_chunk_loads_per_frame: int = 1
@export var max_chunk_unloads_per_frame: int = 4

@export_group("Seed Variation")
@export var base_height_variation: Vector2 = Vector2(-0.8, 1.5)
@export var meadow_radius_variation: Vector2 = Vector2(-2.0, 6.0)
@export var tree_density_variation: Vector2 = Vector2(-0.003, 0.008)
@export var continentalness_frequency_variation: Vector2 = Vector2(-0.0004, 0.0006)
@export var erosion_frequency_variation: Vector2 = Vector2(-0.001, 0.0015)
@export var peaks_valleys_frequency_variation: Vector2 = Vector2(-0.003, 0.004)

func get_meadow_center() -> Vector2:
	return Vector2.ZERO

func runtime_copy_for_seed(seed: int) -> WorldConfig:
	var runtime_config = duplicate() as WorldConfig
	runtime_config.seed_value = seed
	var jitter_rng = RandomNumberGenerator.new()
	jitter_rng.seed = seed
	runtime_config.base_height += jitter_rng.randf_range(base_height_variation.x, base_height_variation.y)
	runtime_config.meadow_radius += jitter_rng.randf_range(meadow_radius_variation.x, meadow_radius_variation.y)
	runtime_config.tree_density += jitter_rng.randf_range(tree_density_variation.x, tree_density_variation.y)
	runtime_config.continentalness_frequency += jitter_rng.randf_range(continentalness_frequency_variation.x, continentalness_frequency_variation.y)
	runtime_config.erosion_frequency += jitter_rng.randf_range(erosion_frequency_variation.x, erosion_frequency_variation.y)
	runtime_config.peaks_valleys_frequency += jitter_rng.randf_range(peaks_valleys_frequency_variation.x, peaks_valleys_frequency_variation.y)
	return runtime_config

func sample_spline(value: float, curve: PackedVector2Array) -> float:
	if curve.is_empty():
		return 0.0
	if curve.size() == 1:
		return curve[0].y
	if value <= curve[0].x:
		return curve[0].y
	if value >= curve[curve.size() - 1].x:
		return curve[curve.size() - 1].y
	for i in range(curve.size() - 1):
		var a: Vector2 = curve[i]
		var b: Vector2 = curve[i + 1]
		if value >= a.x and value <= b.x:
			if b.x == a.x:
				return a.y
			var t: float = (value - a.x) / (b.x - a.x)
			return lerp(a.y, b.y, t)
	return curve[curve.size() - 1].y

func validate() -> bool:
	if biome_library == null:
		push_error("[WorldConfig] biome_library is required")
		return false
	if not biome_library.validate():
		return false
	if chunk_size <= 0 or chunk_size > 100:
		push_error("[WorldConfig] chunk_size %d invalid for infinite" % chunk_size)
		return false
	if max_height <= 0 or max_height > 128:
		push_error("[WorldConfig] max_height %d invalid, must be 1..128" % max_height)
		return false
	if build_extra < 0 or build_extra > 64:
		push_error("[WorldConfig] build_extra %d invalid" % build_extra)
		return false
	if max_build_y <= 0 or max_build_y > 128:
		push_error("[WorldConfig] max_build_y %d invalid, must be 1..128 (increase limit to 128)" % max_build_y)
		return false
	if water_level < 0 or water_level >= max_height:
		push_error("[WorldConfig] water_level %d must be >=0 and < max_height %d" % [water_level, max_height])
		return false
	if tree_density < 0.0 or tree_density > 1.0:
		push_error("[WorldConfig] tree_density %f must be 0..1" % tree_density)
		return false
	if meadow_radius < 0.0 or meadow_radius > 100.0:
		push_error("[WorldConfig] meadow_radius %f invalid for infinite" % meadow_radius)
		return false
	if tree_spacing < 0.1:
		push_error("[WorldConfig] tree_spacing too small")
		return false
	if copper_deposit_chance_per_chunk < 0.0 or copper_deposit_chance_per_chunk > 1.0:
		push_error("[WorldConfig] copper_deposit_chance_per_chunk must be 0..1")
		return false
	if copper_deposit_min_blocks < 1 or copper_deposit_min_blocks > 100:
		push_error("[WorldConfig] copper_deposit_min_blocks must be 1..100")
		return false
	if copper_deposit_max_blocks < copper_deposit_min_blocks or copper_deposit_max_blocks > 100:
		push_error("[WorldConfig] copper_deposit_max_blocks must be >= min and <=100")
		return false
	if copper_surface_exposure_chance < 0.0 or copper_surface_exposure_chance > 1.0:
		push_error("[WorldConfig] copper_surface_exposure_chance must be 0..1")
		return false
	if copper_max_surface_blocks < 0 or copper_max_surface_blocks > 10:
		push_error("[WorldConfig] copper_max_surface_blocks must be 0..10")
		return false
	if render_distance < 1 or render_distance > 20:
		push_error("[WorldConfig] render_distance %d invalid, must be 1..20" % render_distance)
		return false
	if unload_padding < 0 or unload_padding > 10:
		push_error("[WorldConfig] unload_padding %d invalid, must be 0..10" % unload_padding)
		return false
	if max_chunk_loads_per_frame < 1 or max_chunk_loads_per_frame > 10:
		push_error("[WorldConfig] max_chunk_loads_per_frame %d invalid, must be 1..10" % max_chunk_loads_per_frame)
		return false
	if max_chunk_unloads_per_frame < 1 or max_chunk_unloads_per_frame > 20:
		push_error("[WorldConfig] max_chunk_unloads_per_frame %d invalid" % max_chunk_unloads_per_frame)
		return false
	if lake_radius_min < 5 or lake_radius_min > 200:
		push_error("[WorldConfig] lake_radius_min %d invalid" % lake_radius_min)
		return false
	if lake_radius_max < lake_radius_min or lake_radius_max > 300:
		push_error("[WorldConfig] lake_radius_max %d invalid, must be >= min and <=300" % lake_radius_max)
		return false
	if lake_depth < 1 or lake_depth > 20:
		push_error("[WorldConfig] lake_depth %d invalid, must be 1..20" % lake_depth)
		return false
	if lake_grid_size < 50 or lake_grid_size > 1000:
		push_error("[WorldConfig] lake_grid_size %d invalid, must be 50..1000" % lake_grid_size)
		return false
	if lake_chance_per_cell < 0.0 or lake_chance_per_cell > 1.0:
		push_error("[WorldConfig] lake_chance_per_cell %f invalid" % lake_chance_per_cell)
		return false
	if lake_rim_blend < 0.0 or lake_rim_blend > 1.0:
		push_error("[WorldConfig] lake_rim_blend %f invalid" % lake_rim_blend)
		return false
	if river_depth < 1 or river_depth > 10:
		push_error("[WorldConfig] river_depth %d invalid" % river_depth)
		return false
	if river_frequency <= 0.0 or river_frequency > 0.05:
		push_error("[WorldConfig] river_frequency %f invalid" % river_frequency)
		return false
	if param_lattice_step < 1 or param_lattice_step > 8:
		push_error("[WorldConfig] param_lattice_step %d invalid" % param_lattice_step)
		return false
	if continentalness_frequency <= 0.0 or continentalness_frequency > 0.05:
		push_error("[WorldConfig] continentalness_frequency invalid")
		return false
	if erosion_frequency <= 0.0 or erosion_frequency > 0.05:
		push_error("[WorldConfig] erosion_frequency invalid")
		return false
	if peaks_valleys_frequency <= 0.0 or peaks_valleys_frequency > 0.05:
		push_error("[WorldConfig] peaks_valleys_frequency invalid")
		return false
	if temperature_frequency <= 0.0 or temperature_frequency > 0.05:
		push_error("[WorldConfig] temperature_frequency invalid")
		return false
	if humidity_frequency <= 0.0 or humidity_frequency > 0.05:
		push_error("[WorldConfig] humidity_frequency invalid")
		return false
	if relief_scale < 0.0 or relief_scale > 30.0:
		push_error("[WorldConfig] relief_scale %f invalid, must be 0..30" % relief_scale)
		return false
	if shore_influence_min < 0.0 or shore_influence_min > 1.0:
		push_error("[WorldConfig] shore_influence_min %f invalid, must be 0..1" % shore_influence_min)
		return false
	if shore_influence_strong < 0.0 or shore_influence_strong > 1.0:
		push_error("[WorldConfig] shore_influence_strong %f invalid, must be 0..1" % shore_influence_strong)
		return false
	if shore_influence_strong < shore_influence_min:
		push_error("[WorldConfig] shore_influence_strong %f must be >= min %f" % [shore_influence_strong, shore_influence_min])
		return false
	if shore_height_margin < 0 or shore_height_margin > 10:
		push_error("[WorldConfig] shore_height_margin %d invalid, must be 0..10" % shore_height_margin)
		return false
	if shore_waterline_margin < 0 or shore_waterline_margin > 10:
		push_error("[WorldConfig] shore_waterline_margin %d invalid, must be 0..10" % shore_waterline_margin)
		return false
	for variation in [base_height_variation, meadow_radius_variation, tree_density_variation, continentalness_frequency_variation, erosion_frequency_variation, peaks_valleys_frequency_variation]:
		if variation.x > variation.y:
			push_error("[WorldConfig] seed variation minimum must not exceed maximum")
			return false
	return true
