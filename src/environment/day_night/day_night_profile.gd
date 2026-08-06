extends Resource
class_name DayNightProfile

class ProfileKey extends Resource:
	@export var time: float = 0.0
	@export var sky: Color = Color(0, 0, 0)
	@export var ambient_col: Color = Color(0.5, 0.5, 0.5)
	@export var ambient_energy: float = 0.3
	@export var sun_col: Color = Color(1, 1, 1)
	@export var sun_energy: float = 0.5
	@export var shadow_opacity: float = 0.5
	@export var fill_energy: float = 0.05

@export var keys: Array[ProfileKey] = []

var _sorted: bool = false
var _sample: ProfileKey = ProfileKey.new()

func _init():
	if keys.is_empty():
		_build_defaults()

func _build_defaults():
	keys = []
	keys.append(_mk(0.0, Color(0.008, 0.010, 0.032), Color(0.56, 0.64, 0.84), 0.18, Color(0.58, 0.66, 0.84), 0.30, 0.55, 0.015))
	keys.append(_mk(5.0, Color(0.014, 0.022, 0.055), Color(0.58, 0.64, 0.84), 0.19, Color(0.60, 0.68, 0.86), 0.34, 0.55, 0.02))
	keys.append(_mk(6.0, Color(0.06, 0.07, 0.12), Color(0.72, 0.66, 0.72), 0.22, Color(1.0, 0.52, 0.30), 0.55, 0.62, 0.025))
	keys.append(_mk(7.0, Color(0.28, 0.20, 0.18), Color(0.80, 0.68, 0.60), 0.27, Color(1.0, 0.64, 0.40), 0.65, 0.66, 0.035))
	keys.append(_mk(8.0, Color(0.33, 0.48, 0.60), Color(0.867, 0.88, 0.9205), 0.33, Color(1.0, 0.92, 0.78), 0.70, 0.70, 0.04))
	keys.append(_mk(12.0, Color(0.42, 0.56, 0.68), Color(0.905, 0.918, 0.9395), 0.30, Color(1.0, 0.96, 0.88), 0.70, 0.68, 0.035))
	keys.append(_mk(17.0, Color(0.33, 0.48, 0.60), Color(0.867, 0.88, 0.9205), 0.33, Color(1.0, 0.92, 0.78), 0.70, 0.70, 0.04))
	keys.append(_mk(18.0, Color(0.32, 0.22, 0.16), Color(0.80, 0.66, 0.54), 0.27, Color(1.0, 0.56, 0.30), 0.60, 0.66, 0.03))
	keys.append(_mk(19.0, Color(0.028, 0.036, 0.08), Color(0.58, 0.64, 0.84), 0.20, Color(0.60, 0.68, 0.84), 0.38, 0.58, 0.02))
	keys.append(_mk(22.0, Color(0.010, 0.014, 0.035), Color(0.54, 0.60, 0.78), 0.18, Color(0.58, 0.64, 0.82), 0.31, 0.55, 0.015))
	keys.append(_mk(GameClock.HOURS_PER_DAY, Color(0.008, 0.010, 0.032), Color(0.56, 0.64, 0.84), 0.18, Color(0.58, 0.66, 0.84), 0.30, 0.55, 0.015))
	_sort_keys()

func _mk(t: float, sky: Color, amb_col: Color, amb_e: float, sun_col: Color, sun_e: float, sh: float, fill_e: float) -> ProfileKey:
	var k = ProfileKey.new()
	k.time = t
	k.sky = sky
	k.ambient_col = amb_col
	k.ambient_energy = amb_e
	k.sun_col = sun_col
	k.sun_energy = sun_e
	k.shadow_opacity = sh
	k.fill_energy = fill_e
	return k

func _sort_keys():
	keys.sort_custom(func(a, b): return a.time < b.time)
	_sorted = true

func get_interpolated(t: float) -> ProfileKey:
	t = fmod(t, GameClock.HOURS_PER_DAY)
	if t < 0:
		t += GameClock.HOURS_PER_DAY
	if not _sorted:
		_sort_keys()
	if keys.is_empty():
		return _sample

	for i in range(keys.size() - 1):
		var k0 = keys[i]
		var k1 = keys[i + 1]
		if t >= k0.time and t < k1.time:
			var span = k1.time - k0.time
			var f = 0.0
			if span > 0.001:
				f = (t - k0.time) / span
			return _lerp_keys(k0, k1, f)
	return _lerp_keys(keys[0], keys[0], 0.0)

func _lerp_keys(a: ProfileKey, b: ProfileKey, f: float) -> ProfileKey:
	var sf = f * f * (3.0 - 2.0 * f)
	_sample.sky = a.sky.lerp(b.sky, sf)
	_sample.ambient_col = a.ambient_col.lerp(b.ambient_col, sf)
	_sample.ambient_energy = lerp(a.ambient_energy, b.ambient_energy, sf)
	_sample.sun_col = a.sun_col.lerp(b.sun_col, sf)
	_sample.sun_energy = lerp(a.sun_energy, b.sun_energy, sf)
	_sample.shadow_opacity = lerp(a.shadow_opacity, b.shadow_opacity, sf)
	_sample.fill_energy = lerp(a.fill_energy, b.fill_energy, sf)
	return _sample

static func is_day_time(t: float) -> bool:
	t = fmod(t, GameClock.HOURS_PER_DAY)
	if t < 0:
		t += GameClock.HOURS_PER_DAY
	return t >= 6.0 and t < 19.0
