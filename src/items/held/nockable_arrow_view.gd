extends Node3D
class_name NockableArrowView

@export var nock_local_position: Vector3 = Vector3(0.0, -0.35, 0.0)

var _geometries: Array[GeometryInstance3D] = []

func _ready() -> void:
	for child in find_children("*", "GeometryInstance3D", true, false):
		_geometries.append(child as GeometryInstance3D)

func set_fade_progress(progress: float) -> void:
	var transparency := clampf(progress, 0.0, 1.0)
	for geometry in _geometries:
		geometry.transparency = transparency
