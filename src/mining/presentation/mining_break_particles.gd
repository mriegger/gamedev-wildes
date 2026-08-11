extends Node3D
class_name MiningBreakParticles

@onready var _emitters: Array[CPUParticles3D] = [$Dirt01, $Dirt02, $Dirt03]

var _voxel_world: VoxelWorld
var _next_emitter: int = 0

func setup(p_voxel_world: VoxelWorld):
	_voxel_world = p_voxel_world
	_voxel_world.block_edit_committed.connect(_on_block_edit_committed)

func _play_break(position: Vector3):
	var emitter := _emitters[_next_emitter]
	_next_emitter = (_next_emitter + 1) % _emitters.size()
	emitter.global_position = position
	emitter.restart()
	emitter.emitting = true

func _on_block_edit_committed(edit: BlockEdit):
	if not edit.is_mine() or not BlockId.is_chunk_cube(edit.old_id):
		return
	_play_break(Vector3(edit.pos) + Vector3(0.5, 0.5, 0.5))

func _exit_tree():
	if _voxel_world != null and _voxel_world.block_edit_committed.is_connected(_on_block_edit_committed):
		_voxel_world.block_edit_committed.disconnect(_on_block_edit_committed)
	_voxel_world = null
