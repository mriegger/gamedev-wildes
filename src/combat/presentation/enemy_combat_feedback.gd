extends Node3D
class_name EnemyCombatFeedback

const EnemyDamageNumber3DType := preload("res://combat/presentation/enemy_damage_number_3d.gd")

const DAMAGE_NUMBER_POOL_SIZE: int = 24
const DAMAGE_NUMBER_HEIGHT_OFFSET: float = 0.45
const MAX_DAMAGE_NUMBER_CAMERA_SIZE: float = 52.0

var _combat: MeleeCombatCoordinator
var _runtime: EntityRuntime
var _camera: Camera3D
var _damage_numbers: Array[EnemyDamageNumber3DType] = []
var _next_damage_number: int = 0

func _ready() -> void:
	set_process(false)

func setup(combat: MeleeCombatCoordinator, camera: Camera3D) -> void:
	assert(combat != null and camera != null)
	assert(_combat == null and _camera == null)
	_combat = combat
	_camera = camera
	for index in range(DAMAGE_NUMBER_POOL_SIZE):
		var damage_number := EnemyDamageNumber3DType.new()
		damage_number.name = "DamageNumber%02d" % (index + 1)
		add_child(damage_number)
		_damage_numbers.append(damage_number)
	_combat.melee_outcome_committed.connect(_on_melee_outcome_committed)

func bind_runtime(runtime: EntityRuntime) -> void:
	assert(runtime != null)
	assert(_runtime == null)
	_runtime = runtime

func unbind_runtime() -> void:
	_runtime = null
	for damage_number in _damage_numbers:
		damage_number.reset()
	set_process(false)

func _on_melee_outcome_committed(outcome: MeleeOutcome) -> void:
	if _runtime == null or outcome.contact.source_runtime_id != MeleeCombatCoordinator.PLAYER_RUNTIME_ID:
		return
	if _camera.size > MAX_DAMAGE_NUMBER_CAMERA_SIZE:
		return
	var actor := _runtime.get_presented_actor(outcome.contact.target_runtime_id)
	if actor == null or actor.definition == null:
		return
	var damage_number := _damage_numbers[_next_damage_number]
	_next_damage_number = (_next_damage_number + 1) % _damage_numbers.size()
	var position := actor.global_position + Vector3.UP * (actor.definition.body_height + DAMAGE_NUMBER_HEIGHT_OFFSET)
	damage_number.play(position, outcome.applied_damage, get_damage_color(outcome.damage_response))
	set_process(true)

static func get_damage_color(response: int) -> Color:
	assert(DamageAffinityDefinition.is_valid_response(response))
	match response:
		DamageAffinityDefinition.Response.WEAK:
			return CombatPresentationPalette.WEAK_DAMAGE_COLOR
		DamageAffinityDefinition.Response.RESISTANT:
			return CombatPresentationPalette.RESISTANT_DAMAGE_COLOR
		_:
			return CombatPresentationPalette.NEUTRAL_DAMAGE_COLOR

func _process(delta: float) -> void:
	var active := false
	var zoom_visible := _camera != null and _camera.size <= MAX_DAMAGE_NUMBER_CAMERA_SIZE
	for damage_number in _damage_numbers:
		if damage_number.advance(delta, zoom_visible):
			active = true
	if not active:
		set_process(false)

func _exit_tree() -> void:
	if _combat != null and _combat.melee_outcome_committed.is_connected(_on_melee_outcome_committed):
		_combat.melee_outcome_committed.disconnect(_on_melee_outcome_committed)
	_combat = null
	_runtime = null
	_camera = null
