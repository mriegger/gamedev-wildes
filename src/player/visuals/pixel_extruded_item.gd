extends Node3D
class_name PixelExtrudedItem

@export var texture: Texture2D
@export var grip_pixel: Vector2i
@export_range(0.01, 4.0, 0.01) var max_dimension: float = 0.75
@export_range(0.25, 8.0, 0.25) var depth_pixels: float = 1.0

var mesh_instance: MeshInstance3D

func _ready():
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	add_child(mesh_instance)
	rebuild()

func rebuild():
	mesh_instance.mesh = PixelItemMeshBuilder.build(texture, grip_pixel, max_dimension, depth_pixels)
