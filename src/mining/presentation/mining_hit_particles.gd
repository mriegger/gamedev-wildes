extends Node3D
class_name MiningHitParticles

@onready var _emitters: Array[CPUParticles3D] = [$Burst01, $Burst02, $Burst03]

var _animation_driver: PlayerAnimationDriver
var _interactor: PlayerInteractor
var _tint_palette: MiningParticleTintPalette
var _next_emitter: int = 0

func setup(p_animation_driver: PlayerAnimationDriver, p_interactor: PlayerInteractor, p_tint_palette: MiningParticleTintPalette):
	_animation_driver = p_animation_driver
	_interactor = p_interactor
	_tint_palette = p_tint_palette
	_animation_driver.mining_impact.connect(_on_mining_impact)

func _play_hit(position: Vector3, normal: Vector3i, tint: Color):
	var emitter := _emitters[_next_emitter]
	_next_emitter = (_next_emitter + 1) % _emitters.size()
	emitter.direction = Vector3(normal)
	emitter.color = tint
	emitter.global_position = position
	emitter.restart()
	emitter.emitting = true

func _on_mining_impact():
	if not _interactor.has_mining_impact_target():
		return
	var block_id := _interactor.get_mining_impact_block_id()
	if not BlockId.is_chunk_cube(block_id):
		return
	_play_hit(_interactor.get_mining_impact_position(), _interactor.get_mining_impact_normal(), _tint_palette.get_tint(block_id))

func _exit_tree():
	if _animation_driver != null and _animation_driver.mining_impact.is_connected(_on_mining_impact):
		_animation_driver.mining_impact.disconnect(_on_mining_impact)
	_animation_driver = null
	_interactor = null
	_tint_palette = null
