extends Resource
class_name DayNightProfile

## DayNightProfile - stores color gradients and energy curves for each time of day
## Data-driven resource used by DayNightValues + GameClock
## Saved as day_night_profile.tres

class ProfileKey extends Resource:
	@export var time: float = 0.0 # 0..24 hour
	@export var sky: Color = Color(0, 0, 0)
	@export var ambient_col: Color = Color(0.5, 0.5, 0.5)
	@export var ambient_energy: float = 0.3
	@export var sun_col: Color = Color(1, 1, 1)
	@export var sun_energy: float = 0.5
	@export var shadow_opacity: float = 0.5
	@export var fill_energy: float = 0.05

	func to_dict() -> Dictionary:
		return {
			"time": time,
			"sky": sky,
			"ambient_col": ambient_col,
			"ambient_energy": ambient_energy,
			"sun_col": sun_col,
			"sun_energy": sun_energy,
			"shadow_opacity": shadow_opacity,
			"fill_energy": fill_energy,
		}

@export var keys: Array[ProfileKey] = []

var _sorted: bool = false


func _init():
	if keys.is_empty():
		_build_defaults()


func _build_defaults():
	# Mirrors old DayNightCycle._setup_keys() - reduced blown noon 0.32 ambient +0.38 sun =0.70 total vs 2.9
	keys = []
	keys.append(_mk(0.0, Color(0.008, 0.010, 0.032), Color(0.56, 0.64, 0.84), 0.13, Color(0.58, 0.66, 0.84), 0.05, 0.52, 0.015))
	keys.append(_mk(5.0, Color(0.014, 0.022, 0.055), Color(0.58, 0.64, 0.84), 0.15, Color(0.60, 0.68, 0.86), 0.07, 0.50, 0.018))
	keys.append(_mk(6.0, Color(0.06, 0.07, 0.12), Color(0.72, 0.66, 0.72), 0.24, Color(1.0, 0.52, 0.30), 0.20, 0.44, 0.035))
	keys.append(_mk(7.0, Color(0.28, 0.20, 0.18), Color(0.80, 0.68, 0.60), 0.30, Color(1.0, 0.64, 0.40), 0.30, 0.46, 0.05))
	keys.append(_mk(8.0, Color(0.33, 0.48, 0.60), Color(0.867, 0.88, 0.9205), 0.54, Color(1.0, 0.92, 0.78), 0.56, 0.46, 0.10))
	keys.append(_mk(12.0, Color(0.42, 0.56, 0.68), Color(0.905, 0.918, 0.9395), 0.52, Color(1.0, 0.96, 0.88), 0.58, 0.48, 0.11))
	keys.append(_mk(17.0, Color(0.33, 0.48, 0.60), Color(0.867, 0.88, 0.9205), 0.54, Color(1.0, 0.92, 0.78), 0.56, 0.46, 0.10))
	keys.append(_mk(18.0, Color(0.32, 0.22, 0.16), Color(0.80, 0.66, 0.54), 0.28, Color(1.0, 0.56, 0.30), 0.28, 0.46, 0.04))
	keys.append(_mk(19.0, Color(0.028, 0.036, 0.08), Color(0.58, 0.64, 0.84), 0.17, Color(0.60, 0.68, 0.84), 0.09, 0.50, 0.02))
	keys.append(_mk(22.0, Color(0.010, 0.014, 0.035), Color(0.54, 0.60, 0.78), 0.14, Color(0.58, 0.64, 0.82), 0.06, 0.52, 0.015))
	keys.append(_mk(24.0, Color(0.008, 0.010, 0.032), Color(0.56, 0.64, 0.84), 0.13, Color(0.58, 0.66, 0.84), 0.05, 0.52, 0.015))
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


func get_interpolated(t: float) -> Dictionary:
	t = fmod(t, 24.0)
	if t < 0:
		t += 24.0
	if not _sorted:
		_sort_keys()
	if keys.is_empty():
		return {}

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


func _lerp_keys(a: ProfileKey, b: ProfileKey, f: float) -> Dictionary:
	var sf = f * f * (3.0 - 2.0 * f) # smoothstep
	return {
		"sky": a.sky.lerp(b.sky, sf),
		"ambient_col": a.ambient_col.lerp(b.ambient_col, sf),
		"ambient_energy": lerp(a.ambient_energy, b.ambient_energy, sf),
		"sun_col": a.sun_col.lerp(b.sun_col, sf),
		"sun_energy": lerp(a.sun_energy, b.sun_energy, sf),
		"shadow_opacity": lerp(a.shadow_opacity, b.shadow_opacity, sf),
		"fill_energy": lerp(a.fill_energy, b.fill_energy, sf),
	}

func get_phase_name(t: float) -> String:
	t = fmod(t, 24.0)
	if t < 0:
		t += 24.0
	if t >= 19.0 or t < 6.0:
		return "Night (7PM-6AM)"
	elif t >= 6.0 and t < 8.0:
		return "Sunrise (6AM-8AM)"
	elif t >= 8.0 and t < 17.0:
		return "Daytime (8AM-5PM)"
	else:
		return "Sundown (5PM-7PM)"

func is_day(t: float) -> bool:
	t = fmod(t, 24.0)
	if t < 0:
		t += 24.0
	return t >= 6.0 and t < 19.0
