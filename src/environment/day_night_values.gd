extends Node3D
class_name DayNightValues

var profile: DayNightProfile = null
var config: WorldConfig = null

var sun_light: DirectionalLight3D = null
var fill_light: DirectionalLight3D = null
var world_env_node: WorldEnvironment = null
var env: Environment = null
var world_controller: WorldController = null

@export var volumetric_fog_enabled: bool = true:
	set(v):
		volumetric_fog_enabled = v
		if env:
			env.volumetric_fog_enabled = v

func setup(p_clock: GameClock, p_sun: DirectionalLight3D, p_fill: DirectionalLight3D, p_env_node: WorldEnvironment, p_config: WorldConfig, p_world_controller: WorldController):
	sun_light = p_sun
	fill_light = p_fill
	world_env_node = p_env_node
	config = p_config
	world_controller = p_world_controller
	if profile == null:
		profile = load("res://environment/day_night_profile.tres") as DayNightProfile
		if profile == null:
			profile = DayNightProfile.new()
	_duplicate_environment()
	_apply_initial_light_setup()
	p_clock.time_changed.connect(apply)
	apply(p_clock.time_of_day)

func _duplicate_environment():
	if world_env_node and world_env_node.environment:
		env = world_env_node.environment.duplicate()
		world_env_node.environment = env
	else:
		env = Environment.new()
		env.background_mode = Environment.BG_COLOR
		if world_env_node:
			world_env_node.environment = env
	if env:
		env.volumetric_fog_enabled = volumetric_fog_enabled
	if env and RenderingServer.get_rendering_device() == null:
		env.adjustment_saturation = 1.0
		env.adjustment_contrast = 1.0

func _apply_initial_light_setup():
	if sun_light:
		sun_light.shadow_enabled = true
		sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun_light.directional_shadow_split_1 = 0.15
		sun_light.directional_shadow_split_2 = 0.35
		sun_light.directional_shadow_split_3 = 0.70
		sun_light.directional_shadow_blend_splits = true
		sun_light.shadow_bias = 0.05
		sun_light.shadow_normal_bias = 1.2
		sun_light.shadow_blur = 1.2
		sun_light.directional_shadow_max_distance = config.shadow_cast_distance
		sun_light.directional_shadow_fade_start = 0.85
		sun_light.shadow_reverse_cull_face = true
	if fill_light:
		fill_light.shadow_enabled = false
		fill_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS

func apply(time_of_day: float):
	if sun_light == null or env == null or profile == null:
		return

	var is_day = DayNightProfile.is_day_time(time_of_day)
	var azimuth_rad: float
	var elev_factor: float

	if is_day:
		var day_progress = (time_of_day - 6.0) / 13.0
		day_progress = clamp(day_progress, 0.0, 1.0)
		azimuth_rad = day_progress * PI
		elev_factor = sin(day_progress * PI)
	else:
		var nt = time_of_day
		if nt < 6.0:
			nt += GameClock.HOURS_PER_DAY
		var night_progress = (nt - 19.0) / 11.0
		night_progress = clamp(night_progress, 0.0, 1.0)
		azimuth_rad = PI + night_progress * PI
		elev_factor = sin(night_progress * PI)

	var elev_low_deg = 4.5
	var elev_high_day = 58.0
	var elev_high_night = 38.0
	var high = elev_high_day if is_day else elev_high_night
	var elev_deg = lerp(elev_low_deg, high, elev_factor)
	var elev_rad = deg_to_rad(elev_deg)

	var cos_e = cos(elev_rad)
	var sin_e = sin(elev_rad)
	var cos_az = cos(azimuth_rad)
	var sin_az = sin(azimuth_rad)

	var sun_pos = Vector3(cos_az * cos_e, sin_e, sin_az * cos_e)
	var sun_dir = -sun_pos.normalized()

	_set_light_direction(sun_light, sun_dir)

	var blur = 1.0 + (1.0 - elev_factor) * 0.9
	var bias = 0.03 + (1.0 - elev_factor) * 0.09
	sun_light.shadow_blur = blur
	sun_light.shadow_bias = bias
	sun_light.shadow_normal_bias = 1.0 + (1.0 - elev_factor) * 0.6

	if fill_light:
		var fill_pos = Vector3(-cos_az * cos_e * 0.8, sin_e * 0.55, -sin_az * cos_e * 0.8)
		var fill_dir = -fill_pos.normalized()
		_set_light_direction(fill_light, fill_dir)

	var state = profile.get_interpolated(time_of_day)

	env.background_mode = Environment.BG_COLOR
	env.background_color = state.sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = state.ambient_col
	env.ambient_light_energy = state.ambient_energy
	var sky_contrib = 0.08 if not is_day else lerp(0.08, 0.15, elev_factor)
	env.ambient_light_sky_contribution = sky_contrib

	sun_light.light_color = state.sun_col
	sun_light.light_energy = state.sun_energy
	sun_light.shadow_opacity = state.shadow_opacity

	if fill_light:
		var fill_col = state.ambient_col.lerp(state.sky, 0.28)
		fill_light.light_color = fill_col
		fill_light.light_energy = state.fill_energy

	if world_controller:
		world_controller.update_water_tint(state.sky)

func _set_light_direction(light: DirectionalLight3D, dir: Vector3):
	if light == null:
		return
	dir = dir.normalized()
	var up = Vector3.UP
	if abs(dir.dot(up)) > 0.9995:
		up = Vector3.FORWARD
	var origin = light.global_transform.origin
	if origin == Vector3.ZERO:
		origin = Vector3(0, 25, 0)
		light.global_transform.origin = origin
	light.look_at(origin + dir, up)
