extends Node3D
class_name MiningBreakParticles

@onready var _emitters: Array[CPUParticles3D] = [$Dirt01, $Dirt02, $Dirt03]

var _voxel_world: VoxelWorld
var _tint_palette: MiningParticleTintPalette
var _next_emitter: int = 0

func setup(p_voxel_world: VoxelWorld, p_tint_palette: MiningParticleTintPalette):
	_voxel_world = p_voxel_world
	_tint_palette = p_tint_palette
	_voxel_world.block_edit_committed.connect(_on_block_edit_committed)

func _play_break(position: Vector3, tint: Color):
	var emitter := _emitters[_next_emitter]
	_next_emitter = (_next_emitter + 1) % _emitters.size()
	emitter.color = tint
	emitter.global_position = position
	emitter.restart()
	emitter.emitting = true

func _on_block_edit_committed(edit: BlockEdit):
	if not edit.is_mine() or not BlockId.is_chunk_cube(edit.old_id):
		return
	_play_break(Vector3(edit.pos) + Vector3(0.5, 0.5, 0.5), _tint_palette.get_tint(edit.old_id))

func _exit_tree():
	if _voxel_world != null and _voxel_world.block_edit_committed.is_connected(_on_block_edit_committed):
		_voxel_world.block_edit_committed.disconnect(_on_block_edit_committed)
	_voxel_world = null
	_tint_palette = null
