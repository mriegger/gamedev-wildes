extends Node3D
class_name LootDropView

signal hover_changed(hovered: bool)

const BASE_HEIGHT: float = 0.58
const BOB_DISTANCE: float = 0.07
const SPIN_SPEED: float = 0.6
const BOB_SPEED: float = SPIN_SPEED * 4.0
const ENTRY_PHASE_STEP: float = 2.399963
const ANIMATION_CYCLE_SECONDS: float = TAU / SPIN_SPEED
const ITEM_MAX_DIMENSION: float = 0.75
const ITEM_DEPTH_PIXELS: float = 2.0
const FALL_GRAVITY: float = 18.0
const MINIMUM_FALL_DURATION: float = 0.1

@onready var _visual_root: Node3D = $VisualRoot as Node3D
@onready var _item_mesh: MeshInstance3D = $VisualRoot/Item as MeshInstance3D
@onready var _model: MeshInstance3D = $VisualRoot/Model as MeshInstance3D
@onready var _shadow: MeshInstance3D = $Shadow as MeshInstance3D
@onready var _pickup_area: Area3D = $PickupArea as Area3D
@onready var _hover_box: Node3D = $HoverBox as Node3D

var _elapsed_seconds: float = 0.0
var _animation_phase: float = 0.0
var _configured: bool = false
var _falling: bool = false
var _resting_position: Vector3

static func build_item_mesh(icon: Texture2D) -> ArrayMesh:
	return PixelItemMeshBuilder.build_centered(icon, ITEM_MAX_DIMENSION, ITEM_DEPTH_PIXELS)

func _ready() -> void:
	_create_hover_box()
	_pickup_area.mouse_entered.connect(_on_mouse_entered)
	_pickup_area.mouse_exited.connect(_on_mouse_exited)
	set_process(_configured)

func setup(definition: ItemDefinition, mesh: ArrayMesh, entry_id: int) -> void:
	assert(definition != null and definition.icon != null)
	assert(is_finite(definition.world_presentation_scale) and definition.world_presentation_scale > 0.0)
	assert(entry_id >= 1)
	if definition.world_model != null:
		_item_mesh.visible = false
		_model.mesh = definition.world_model
		_model.material_override = definition.world_material
		_model.scale = Vector3.ONE * definition.world_presentation_scale
		_model.visible = true
	else:
		assert(mesh != null)
		_model.visible = false
		_item_mesh.mesh = mesh
		_item_mesh.scale = Vector3.ONE * definition.world_presentation_scale
		_item_mesh.visible = true
	_elapsed_seconds = 0.0
	_animation_phase = fposmod(float(entry_id) * ENTRY_PHASE_STEP, TAU)
	_configured = true
	_apply_animation()
	if is_inside_tree():
		set_process(true)

func _process(delta: float) -> void:
	_elapsed_seconds = fposmod(_elapsed_seconds + delta, ANIMATION_CYCLE_SECONDS)
	_apply_animation()

func _apply_animation() -> void:
	var bob_phase := _elapsed_seconds * BOB_SPEED + _animation_phase
	var bob_progress := sin(bob_phase)
	_visual_root.position = Vector3(0.0, BASE_HEIGHT + bob_progress * BOB_DISTANCE, 0.0)
	_visual_root.rotation.y = _elapsed_seconds * SPIN_SPEED + _animation_phase
	var shadow_scale := 0.9 - bob_progress * 0.08
	_shadow.scale = Vector3(shadow_scale, 1.0, shadow_scale)

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
