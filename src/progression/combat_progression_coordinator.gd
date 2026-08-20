extends RefCounted
class_name CombatProgressionCoordinator

var _player_stats: ActorStats
var _inventory: InventoryModel
var _entity_catalog: EntityCatalog
var _item_proficiency: ItemProficiency

func setup(
	p_player_stats: ActorStats,
	p_inventory: InventoryModel,
	p_entity_catalog: EntityCatalog,
	p_item_proficiency: ItemProficiency,
):
	assert(p_player_stats != null)
	assert(p_inventory != null)
	assert(p_entity_catalog != null)
	assert(p_item_proficiency != null)
	_player_stats = p_player_stats
	_inventory = p_inventory
	_entity_catalog = p_entity_catalog
	_item_proficiency = p_item_proficiency

func record_melee_outcome(outcome: MeleeOutcome):
	assert(outcome != null)
	var contact := outcome.contact
	if contact.source_runtime_id == MeleeCombatCoordinator.PLAYER_RUNTIME_ID:
		_award_weapon_damage(outcome.source_item_id, outcome.applied_damage)
		if outcome.target_defeated:
			_award_defeat(contact.target_definition_id)
	elif contact.target_runtime_id == MeleeCombatCoordinator.PLAYER_RUNTIME_ID:
		_award_armor_damage(outcome.applied_damage)

func record_projectile_outcome(outcome: ProjectileOutcome):
	assert(outcome != null)
	_award_weapon_damage(outcome.source_item_id, outcome.applied_damage)
	if outcome.target_defeated:
		_award_defeat(outcome.contact.target_definition_id)

func _award_defeat(entity_id: StringName):
	assert(_entity_catalog.has_definition(entity_id))
	_player_stats.add_experience(_entity_catalog.get_definition(entity_id).experience_reward)

func _award_weapon_damage(item_id: StringName, damage: float):
	assert(_item_proficiency.has_proficiency(item_id))
	_item_proficiency.add_experience(item_id, damage)

func _award_armor_damage(damage: float):
	for armor_slot in range(ArmorDefinition.SLOT_COUNT):
		var armor := _inventory.get_equipped_armor(armor_slot)
		if armor != null:
			_item_proficiency.add_experience(armor.id, damage)
