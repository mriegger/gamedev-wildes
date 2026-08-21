extends Node3D
class_name LootDropView

signal hover_changed(hovered: bool)

const FALL_GRAVITY: float = 18.0
const MINIMUM_FALL_DURATION: float = 0.1

@onready var _icon: Sprite3D = $Icon as Sprite3D
@onready var _model: MeshInstance3D = $Model as MeshInstance3D
@onready var _pickup_area: Area3D = $PickupArea as Area3D
@onready var _hover_box: Node3D = $HoverBox as Node3D

var _falling: bool = false
var _resting_position: Vector3

func _ready() -> void:
	_create_hover_box()
	_pickup_area.mouse_entered.connect(_on_mouse_entered)
	_pickup_area.mouse_exited.connect(_on_mouse_exited)

func setup(definition: ItemDefinition) -> void:
	assert(definition != null and definition.icon != null)
	assert(is_finite(definition.world_presentation_scale) and definition.world_presentation_scale > 0.0)
	if definition.world_model != null:
		_icon.visible = false
		_model.mesh = definition.world_model
		_model.material_override = definition.world_material
		_model.scale = Vector3.ONE * definition.world_presentation_scale
		_model.visible = true
	else:
		_model.visible = false
		_icon.texture = definition.icon
		_icon.scale = Vector3.ONE * definition.world_presentation_scale
		_icon.visible = true

func sync_world_position(world_position: Vector3) -> void:
	assert(world_position.is_finite())
	_resting_position = world_position
	if not _falling:
		global_position = world_position

func begin_fall(world_position: Vector3) -> void:
	assert(world_position.is_finite())
	var fall_height := world_position.y - _resting_position.y
	if fall_height <= 0.0:
		global_position = _resting_position
		return
	_falling = true
	global_position = world_position
	var duration := maxf(sqrt(2.0 * fall_height / FALL_GRAVITY), MINIMUM_FALL_DURATION)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(self, "global_position", _resting_position, duration)
	tween.finished.connect(_finish_fall)

func is_falling() -> bool:
	return _falling

func _on_mouse_entered() -> void:
	_hover_box.visible = true
	hover_changed.emit(true)

func _on_mouse_exited() -> void:
	_hover_box.visible = false
	hover_changed.emit(false)

func _create_hover_box() -> void:
	var edge_thickness := 0.03
	var half_width := 0.35
	var half_height := 0.25
	var half_depth := 0.725
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.92, 0.08, 1.0)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var edges := [
		{"size": Vector3(0.7, edge_thickness, edge_thickness), "position": Vector3(0.0, half_height, half_depth)},
		{"size": Vector3(0.7, edge_thickness, edge_thickness), "position": Vector3(0.0, half_height, -half_depth)},
		{"size": Vector3(0.7, edge_thickness, edge_thickness), "position": Vector3(0.0, -half_height, half_depth)},
		{"size": Vector3(0.7, edge_thickness, edge_thickness), "position": Vector3(0.0, -half_height, -half_depth)},
		{"size": Vector3(edge_thickness, 0.5, edge_thickness), "position": Vector3(half_width, 0.0, half_depth)},
		{"size": Vector3(edge_thickness, 0.5, edge_thickness), "position": Vector3(half_width, 0.0, -half_depth)},
		{"size": Vector3(edge_thickness, 0.5, edge_thickness), "position": Vector3(-half_width, 0.0, half_depth)},
		{"size": Vector3(edge_thickness, 0.5, edge_thickness), "position": Vector3(-half_width, 0.0, -half_depth)},
		{"size": Vector3(edge_thickness, edge_thickness, 1.45), "position": Vector3(half_width, half_height, 0.0)},
		{"size": Vector3(edge_thickness, edge_thickness, 1.45), "position": Vector3(half_width, -half_height, 0.0)},
		{"size": Vector3(edge_thickness, edge_thickness, 1.45), "position": Vector3(-half_width, half_height, 0.0)},
		{"size": Vector3(edge_thickness, edge_thickness, 1.45), "position": Vector3(-half_width, -half_height, 0.0)},
	]
	for edge in edges:
		var mesh_instance := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = edge["size"]
		mesh_instance.mesh = mesh
		mesh_instance.position = edge["position"]
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_instance.material_override = material
		_hover_box.add_child(mesh_instance)

func _finish_fall() -> void:
	_falling = false
	global_position = _resting_position
