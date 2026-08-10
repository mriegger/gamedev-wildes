extends Node
class_name EntityVisualFader

enum Phase {
	NOT_READY,
	FADING_IN,
	VISIBLE,
	FADING_OUT,
	HIDDEN,
}

@export_range(0.01, 2.0, 0.01) var fade_in_seconds: float = 0.4
@export_range(0.01, 2.0, 0.01) var fade_out_seconds: float = 0.35

var _geometries: Array[GeometryInstance3D] = []
var _baseline_transparencies: Array[float] = []
var _phase: Phase = Phase.NOT_READY
var _elapsed: float = 0.0
var _opacity: float = 0.0
var _fade_out_start_opacity: float = 0.0

func setup(visual_root: Node3D):
	assert(visual_root != null)
	assert(_phase == Phase.NOT_READY)
	assert(can_fade(visual_root))
	_collect_geometries(visual_root)
	_phase = Phase.FADING_IN
	_set_opacity(0.0)

func advance(delta: float) -> bool:
	assert(delta >= 0.0)
	assert(_phase != Phase.NOT_READY)
	match _phase:
		Phase.FADING_IN:
			_elapsed = minf(_elapsed + delta, fade_in_seconds)
			var progress := _smooth_progress(_elapsed, fade_in_seconds)
			_set_opacity(progress)
			if _elapsed >= fade_in_seconds:
				_phase = Phase.VISIBLE
		Phase.FADING_OUT:
			_elapsed = minf(_elapsed + delta, fade_out_seconds)
			var progress := _smooth_progress(_elapsed, fade_out_seconds)
			_set_opacity(lerpf(_fade_out_start_opacity, 0.0, progress))
			if _elapsed >= fade_out_seconds:
				_phase = Phase.HIDDEN
	return _phase == Phase.HIDDEN

func begin_fade_out():
	assert(_phase in [Phase.FADING_IN, Phase.VISIBLE])
	_fade_out_start_opacity = _opacity
	_elapsed = 0.0
	_phase = Phase.FADING_OUT

func get_opacity() -> float:
	return _opacity

func can_fade(visual_root: Node) -> bool:
	if visual_root == null:
		return false
	if visual_root is GeometryInstance3D:
		return true
	for child in visual_root.get_children():
		if can_fade(child):
			return true
	return false

func _collect_geometries(node: Node):
	if node is GeometryInstance3D:
		var geometry := node as GeometryInstance3D
		_geometries.append(geometry)
		_baseline_transparencies.append(geometry.transparency)
	for child in node.get_children():
		_collect_geometries(child)

func _set_opacity(value: float):
	_opacity = clampf(value, 0.0, 1.0)
	for index in _geometries.size():
		_geometries[index].transparency = lerpf(1.0, _baseline_transparencies[index], _opacity)

func _smooth_progress(elapsed: float, duration: float) -> float:
	return smoothstep(0.0, 1.0, clampf(elapsed / duration, 0.0, 1.0))
