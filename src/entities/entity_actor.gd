extends Node3D
class_name EntityActor

@export_node_path("Node") var animation_driver_path: NodePath

@onready var model_root: Node3D = $ModelRoot as Node3D

var runtime_id: int = -1
var definition: EntityDefinition
var velocity: Vector3 = Vector3.ZERO
var on_ground: bool = true
var max_speed: float = 1.0
var animation_driver: EntityAnimationDriver

func _ready():
	set_process(false)

func setup(p_runtime_id: int, p_definition: EntityDefinition):
	assert(p_runtime_id >= 0)
	assert(p_definition != null)
	runtime_id = p_runtime_id
	definition = p_definition
	animation_driver = get_node(animation_driver_path) as EntityAnimationDriver
	assert(animation_driver != null)
	animation_driver.setup(self)
	set_process(true)

func _process(delta: float):
	animation_driver.advance(delta)

func play_attack(duration: float):
	animation_driver.play_attack(duration)

func play_hit(local_hit_direction: Vector3):
	animation_driver.play_hit(local_hit_direction)

func get_world_bounds() -> AABB:
	assert(definition != null)
	var half_width := definition.body_width * 0.5
	return AABB(
		global_position + Vector3(-half_width, 0.0, -half_width),
		Vector3(definition.body_width, definition.body_height, definition.body_width)
	)
