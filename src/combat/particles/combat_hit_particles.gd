extends Node3D
class_name CombatHitParticles

@onready var _bursts: Array[CombatHitParticleBurst] = [$Burst01, $Burst02, $Burst03, $Burst04]

var _combat: MeleeCombatCoordinator
var _catalog: CombatHitParticleCatalog
var _next_burst: int = 0

func setup(p_combat: MeleeCombatCoordinator, p_catalog: CombatHitParticleCatalog):
	assert(p_combat != null)
	assert(p_catalog != null)
	_combat = p_combat
	_catalog = p_catalog
	_combat.melee_outcome_committed.connect(_on_melee_outcome_committed)
	_combat.projectile_outcome_committed.connect(_on_projectile_outcome_committed)

func _on_melee_outcome_committed(outcome: MeleeOutcome):
	var contact := outcome.contact
	_play_contact(contact.source_definition_id, contact.target_definition_id, contact.world_position, contact.hit_direction)

func _on_projectile_outcome_committed(outcome: ProjectileOutcome):
	var contact := outcome.contact
	_play_contact(MeleeCombatCoordinator.PLAYER_DEFINITION_ID, contact.target_definition_id, contact.world_position, contact.hit_direction)

func _play_contact(source_definition_id: StringName, target_definition_id: StringName, position: Vector3, direction: Vector3):
	var profile := _catalog.get_profile(source_definition_id, target_definition_id)
	if profile == null:
		return
	var burst := _bursts[_next_burst]
	_next_burst = (_next_burst + 1) % _bursts.size()
	burst.play(position, direction, profile.primary_color, profile.accent_color)

func _exit_tree():
	if _combat != null and _combat.melee_outcome_committed.is_connected(_on_melee_outcome_committed):
		_combat.melee_outcome_committed.disconnect(_on_melee_outcome_committed)
	if _combat != null and _combat.projectile_outcome_committed.is_connected(_on_projectile_outcome_committed):
		_combat.projectile_outcome_committed.disconnect(_on_projectile_outcome_committed)
	_combat = null
	_catalog = null
