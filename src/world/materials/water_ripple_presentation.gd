extends RefCounted
class_name WaterRipplePresentation

const MAXIMUM_RIPPLES: int = 8

var _material: ShaderMaterial
var _duration: float
var _events := PackedVector4Array()
var _motions := PackedVector4Array()
var _next_index: int = 0

func setup(material: ShaderMaterial, duration: float) -> void:
	assert(material != null and duration > 0.0)
	_material = material
	_duration = duration
	_next_index = 0
	_events.resize(MAXIMUM_RIPPLES)
	_events.fill(Vector4(0.0, 0.0, duration, 0.0))
	_motions.resize(MAXIMUM_RIPPLES)
	_motions.fill(Vector4(0.0, 1.0, 0.0, 0.0))
	_apply_events()

func play(position: Vector3, planar_velocity: Vector2) -> void:
	assert(_material != null)
	assert(position.is_finite() and planar_velocity.is_finite())
	var speed := planar_velocity.length()
	var direction := planar_velocity / speed if speed > 0.001 else Vector2.UP
	_events[_next_index] = Vector4(position.x, position.z, 0.0, 1.0)
	_motions[_next_index] = Vector4(direction.x, direction.y, speed, 0.0)
	_next_index = (_next_index + 1) % MAXIMUM_RIPPLES
	_apply_events()

func try_set_strength(strength: float) -> bool:
	if _material == null or not is_finite(strength) or strength < 0.0 or strength > 1.0:
		return false
	_material.set_shader_parameter(&"ripple_strength", strength)
	return true

func tick(delta: float) -> void:
	assert(delta >= 0.0)
	if _material == null:
		return
	var changed := false
	for index in range(_events.size()):
		var event := _events[index]
		if event.w <= 0.0:
			continue
		event.z += delta
		if event.z >= _duration:
			event.z = _duration
			event.w = 0.0
		_events[index] = event
		changed = true
	if changed:
		_apply_events()

func clear() -> void:
	if _material != null:
		_events.fill(Vector4(0.0, 0.0, _duration, 0.0))
		_motions.fill(Vector4(0.0, 1.0, 0.0, 0.0))
		_apply_events()
	_material = null
	_next_index = 0

func get_events() -> PackedVector4Array:
	return _events.duplicate()

func _apply_events() -> void:
	_material.set_shader_parameter(&"ripple_events", _events)
	_material.set_shader_parameter(&"ripple_motions", _motions)
