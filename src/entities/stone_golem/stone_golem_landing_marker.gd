extends Node3D
class_name StoneGolemLandingMarker

func _ready() -> void:
	top_level = true
	hide_marker()

func show_at(world_position: Vector3) -> void:
	global_position = world_position
	visible = true

func hide_marker() -> void:
	visible = false
