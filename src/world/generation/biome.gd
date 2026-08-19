extends Resource
class_name Biome

@export var biome_id: String = ""

@export_group("Parameter Ranges")
@export_range(0.0, 1.0) var min_temperature: float = 0.0
@export_range(0.0, 1.0) var max_temperature: float = 1.0
@export_range(0.0, 1.0) var min_humidity: float = 0.0
@export_range(0.0, 1.0) var max_humidity: float = 1.0
@export_range(0.0, 1.0) var min_continentalness: float = 0.0
@export_range(0.0, 1.0) var max_continentalness: float = 1.0
@export_range(0.0, 1.0) var min_erosion: float = 0.0
@export_range(0.0, 1.0) var max_erosion: float = 1.0
@export_range(0.0, 1.0) var min_peaks_valleys: float = 0.0
@export_range(0.0, 1.0) var max_peaks_valleys: float = 1.0

@export_group("Surface")
@export var surface_block: BlockId.Type = BlockId.Type.GRASS
@export var shore_block: BlockId.Type = BlockId.Type.SAND

@export_group("Vegetation")
@export_range(0.0, 0.1) var tree_density: float = 0.01
@export_range(0.0, 1.0, 0.01) var foliage_density: float = 0.0

# Fixed indices for PackedFloat32Array params: 0=continentalness, 1=erosion, 2=peaks_valleys, 3=temperature, 4=humidity
const IDX_CONTINENTALNESS: int = 0
const IDX_EROSION: int = 1
const IDX_PEAKS_VALLEYS: int = 2
const IDX_TEMPERATURE: int = 3
const IDX_HUMIDITY: int = 4

func validate(source: String) -> bool:
	if foliage_density < 0.0 or foliage_density > 1.0:
		push_error("[Biome] Foliage density must be 0..1 at %s" % source)
		return false
	return true

func distance_squared_to(params: PackedFloat32Array) -> float:
	var d: float = 0.0
	var v: float
	v = params[IDX_TEMPERATURE]
	if v < min_temperature: d += (min_temperature - v) * (min_temperature - v)
	elif v > max_temperature: d += (v - max_temperature) * (v - max_temperature)
	v = params[IDX_HUMIDITY]
	if v < min_humidity: d += (min_humidity - v) * (min_humidity - v)
	elif v > max_humidity: d += (v - max_humidity) * (v - max_humidity)
	v = params[IDX_CONTINENTALNESS]
	if v < min_continentalness: d += (min_continentalness - v) * (min_continentalness - v)
	elif v > max_continentalness: d += (v - max_continentalness) * (v - max_continentalness)
	v = params[IDX_EROSION]
	if v < min_erosion: d += (min_erosion - v) * (min_erosion - v)
	elif v > max_erosion: d += (v - max_erosion) * (v - max_erosion)
	v = params[IDX_PEAKS_VALLEYS]
	if v < min_peaks_valleys: d += (min_peaks_valleys - v) * (min_peaks_valleys - v)
	elif v > max_peaks_valleys: d += (v - max_peaks_valleys) * (v - max_peaks_valleys)
	return d
