extends RefCounted
class_name GameSettings

const SETTINGS_PATH := "user://settings.json"
const MAX_3D_RENDER_SIZE := Vector2(2560.0, 1440.0)
const ANTI_ALIASING_OFF := 0
const ANTI_ALIASING_FXAA := 1
const ANTI_ALIASING_TAA := 2
const SHADOW_RANGE_LOW := 0
const SHADOW_RANGE_MEDIUM := 1
const SHADOW_RANGE_HIGH := 2

var frame_rate_limit: int = 120
var render_scale: float = 1.0
var anti_aliasing: int = ANTI_ALIASING_FXAA
var volumetric_fog_enabled: bool = false
var sun_shadows_enabled: bool = true
var shadow_range: int = SHADOW_RANGE_MEDIUM
var torch_shadow_count: int = 1
var dungeon_torch_shadow_count: int = 6
var music_volume: float = 0.8
var ambient_volume: float = 1.0
var music_volume: float = 0.7
var birds_enabled: bool = true
var persist_changes: bool = false

static func load_from_disk() -> GameSettings:
	var settings := GameSettings.new()
	settings.persist_changes = true
	if not FileAccess.file_exists(SETTINGS_PATH):
		return settings
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return settings
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		settings._apply_dict(parsed as Dictionary)
	return settings

func save_to_disk() -> bool:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(to_dict()))
	file.close()
	return true

func apply_display(viewport: Viewport):
	Engine.max_fps = frame_rate_limit
	var viewport_size := Vector2(viewport.size)
	var width_scale := MAX_3D_RENDER_SIZE.x / maxf(viewport_size.x, 1.0)
	var height_scale := MAX_3D_RENDER_SIZE.y / maxf(viewport_size.y, 1.0)
	var native_scale := minf(1.0, minf(width_scale, height_scale))
	viewport.scaling_3d_scale = native_scale * render_scale
	viewport.use_taa = anti_aliasing == ANTI_ALIASING_TAA
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if anti_aliasing == ANTI_ALIASING_FXAA else Viewport.SCREEN_SPACE_AA_DISABLED

func get_shadow_distance() -> float:
	match shadow_range:
		SHADOW_RANGE_LOW:
			return 64.0
		SHADOW_RANGE_HIGH:
			return 128.0
	return 96.0

func get_shadow_chunk_radius() -> int:
	match shadow_range:
		SHADOW_RANGE_LOW:
			return 1
		SHADOW_RANGE_HIGH:
			return 3
	return 2

func to_dict() -> Dictionary:
	return {
		"frame_rate_limit": frame_rate_limit,
		"render_scale": render_scale,
		"anti_aliasing": anti_aliasing,
		"volumetric_fog_enabled": volumetric_fog_enabled,
		"sun_shadows_enabled": sun_shadows_enabled,
		"shadow_range": shadow_range,
		"torch_shadow_count": torch_shadow_count,
		"dungeon_torch_shadow_count": dungeon_torch_shadow_count,
		"music_volume": music_volume,
		"ambient_volume": ambient_volume,
		"music_volume": music_volume,
		"birds_enabled": birds_enabled,
	}

func _apply_dict(data: Dictionary):
	var loaded_fps := int(data.get("frame_rate_limit", frame_rate_limit))
	frame_rate_limit = loaded_fps if loaded_fps in [0, 60, 90, 120] else 120
	var loaded_scale := float(data.get("render_scale", render_scale))
	render_scale = loaded_scale if loaded_scale in [0.75, 0.85, 1.0] else 1.0
	anti_aliasing = clampi(int(data.get("anti_aliasing", anti_aliasing)), ANTI_ALIASING_OFF, ANTI_ALIASING_TAA)
	volumetric_fog_enabled = bool(data.get("volumetric_fog_enabled", volumetric_fog_enabled))
	sun_shadows_enabled = bool(data.get("sun_shadows_enabled", sun_shadows_enabled))
	shadow_range = clampi(int(data.get("shadow_range", shadow_range)), SHADOW_RANGE_LOW, SHADOW_RANGE_HIGH)
	var loaded_torch_shadows := int(data.get("torch_shadow_count", torch_shadow_count))
	torch_shadow_count = loaded_torch_shadows if loaded_torch_shadows in [0, 1, 2, 4] else 1
	var loaded_dungeon_torch_shadows := int(data.get("dungeon_torch_shadow_count", dungeon_torch_shadow_count))
	dungeon_torch_shadow_count = loaded_dungeon_torch_shadows if loaded_dungeon_torch_shadows in [0, 2, 4, 6] else 6
	var loaded_music_volume := float(data.get("music_volume", music_volume))
	music_volume = clampf(loaded_music_volume, 0.0, 1.0)
	var loaded_ambient_vol := float(data.get("ambient_volume", ambient_volume))
	ambient_volume = clampf(loaded_ambient_vol, 0.0, 1.0)
	var loaded_music_vol := float(data.get("music_volume", music_volume))
	music_volume = clampf(loaded_music_vol, 0.0, 1.0)
	birds_enabled = bool(data.get("birds_enabled", birds_enabled))
