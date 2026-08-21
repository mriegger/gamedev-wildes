extends RefCounted
class_name DeathTipCoordinator

const FOOD_ITEM_IDS: Array[StringName] = [&"apple", &"pumpkin"]
const HEALTH_POTION_ITEM_ID: StringName = &"health_potion"
const RECOVERY_ITEM_IDS: Array[StringName] = [&"apple", &"pumpkin", &"health_potion"]
const HAMMER_EQUIPMENT_TYPE_ID: StringName = &"weapon_hammer"
const CROWD_ENEMY_THRESHOLD: int = 3
const CROWD_RADIUS: float = 4.0
const NO_WEAPON_TIP: String = "Tip: Craft a weapon at the Anvil to defend yourself against enemies."
const HARVEST_FOOD_TIP: String = "Tip: Harvest food to replenish health during combat."
const CRAFT_CAULDRON_TIP: String = "Tip: Craft a Cauldron to make health potions."
const USE_RECOVERY_ITEM_TIP: String = "Tip: Eat food or drink a health potion to replenish your health."
const EQUIP_ARMOR_TIP: String = "Tip: Craft armor at the Anvil and equip it to improve your defense."
const CROWD_TIP: String = "Tip: Use a Hammer to more easily manage crowds of enemies."
const PROGRESSION_TIP: String = "Tip: Use Skill points to increase your stats in the Progression tab of the Crafting menu."
const DAMAGE_TYPE_ORDER: Array[StringName] = [&"slash", &"blunt", &"pierce"]

var _inventory: InventoryModel
var _consumption: ItemConsumptionCoordinator
var _combat: MeleeCombatCoordinator
var _entity_catalog: EntityCatalog
var _rng := RandomNumberGenerator.new()
var _consumed_recovery_item: bool = false
var _resisted_targets: Dictionary[int, StringName] = {}
var _hammer_targets: Dictionary[int, StringName] = {}
var _last_incoming_contact: MeleeContact

func _init(random_seed: int = 0) -> void:
	if random_seed == 0:
		_rng.randomize()
	else:
		_rng.seed = random_seed

func setup(
	inventory: InventoryModel,
	consumption: ItemConsumptionCoordinator,
	combat: MeleeCombatCoordinator,
	entity_catalog: EntityCatalog,
) -> void:
	assert(inventory != null and consumption != null and combat != null and entity_catalog != null)
	assert(_inventory == null and _consumption == null and _combat == null and _entity_catalog == null)
	_inventory = inventory
	_consumption = consumption
	_combat = combat
	_entity_catalog = entity_catalog
	_consumption.item_consumed.connect(_on_item_consumed)
	_combat.melee_outcome_committed.connect(_on_melee_outcome_committed)
	_combat.projectile_outcome_committed.connect(_on_projectile_outcome_committed)

func shutdown() -> void:
	if _consumption != null and _consumption.item_consumed.is_connected(_on_item_consumed):
		_consumption.item_consumed.disconnect(_on_item_consumed)
	if _combat != null:
		if _combat.melee_outcome_committed.is_connected(_on_melee_outcome_committed):
			_combat.melee_outcome_committed.disconnect(_on_melee_outcome_committed)
		if _combat.projectile_outcome_committed.is_connected(_on_projectile_outcome_committed):
			_combat.projectile_outcome_committed.disconnect(_on_projectile_outcome_committed)
	_inventory = null
	_consumption = null
	_combat = null
	_entity_catalog = null
	reset_life()

func reset_life() -> void:
	_consumed_recovery_item = false
	reset_entity_context()

func reset_entity_context() -> void:
	_resisted_targets.clear()
	_hammer_targets.clear()
	_last_incoming_contact = null

func choose_tip(nearby_enemy_count: int) -> String:
	var applicable := get_applicable_tips(nearby_enemy_count)
	return applicable[_rng.randi_range(0, applicable.size() - 1)]

func get_applicable_tips(nearby_enemy_count: int) -> Array[String]:
	assert(_inventory != null and _entity_catalog != null)
	assert(nearby_enemy_count >= 0)
	if not CombatInventoryRules.has_ready_weapon(_inventory):
		return [NO_WEAPON_TIP]
	var applicable: Array[String] = []
	if not _consumed_recovery_item:
		var has_food := _has_any_item(FOOD_ITEM_IDS)
		var has_health_potion := _has_any_item([HEALTH_POTION_ITEM_ID])
		if has_health_potion:
			applicable.append(USE_RECOVERY_ITEM_TIP)
		elif has_food:
			applicable.append(CRAFT_CAULDRON_TIP)
		else:
			applicable.append(HARVEST_FOOD_TIP)
	if not _has_equipped_armor():
		applicable.append(EQUIP_ARMOR_TIP)
	var affinity_tip := _build_killer_affinity_tip()
	if not affinity_tip.is_empty():
		applicable.append(affinity_tip)
	if nearby_enemy_count > CROWD_ENEMY_THRESHOLD and not _used_hammer_against_killer():
		applicable.append(CROWD_TIP)
	if applicable.is_empty():
		applicable.append(PROGRESSION_TIP)
	return applicable

static func count_nearby_hostiles(actors: Array[EntityActor], player_position: Vector3) -> int:
	assert(player_position.is_finite())
	var count := 0
	for actor in actors:
		if actor == null or actor.definition == null or not actor.definition.hostile_to_player:
			continue
		var offset := Vector2(actor.global_position.x - player_position.x, actor.global_position.z - player_position.z)
		if offset.length_squared() <= CROWD_RADIUS * CROWD_RADIUS:
			count += 1
	return count

func _on_item_consumed(item_id: StringName) -> void:
	if item_id in RECOVERY_ITEM_IDS:
		_consumed_recovery_item = true

func _on_melee_outcome_committed(outcome: MeleeOutcome) -> void:
	if outcome.contact.target_runtime_id == MeleeCombatCoordinator.PLAYER_RUNTIME_ID:
		_last_incoming_contact = outcome.contact
	if outcome.contact.source_runtime_id == MeleeCombatCoordinator.PLAYER_RUNTIME_ID:
		if _is_hammer(outcome.source_item_id):
			_hammer_targets[outcome.contact.target_runtime_id] = outcome.contact.target_definition_id
	if (
		outcome.contact.source_runtime_id == MeleeCombatCoordinator.PLAYER_RUNTIME_ID
		and outcome.damage_response == DamageAffinityDefinition.Response.RESISTANT
	):
		_resisted_targets[outcome.contact.target_runtime_id] = outcome.contact.target_definition_id

func _is_hammer(item_id: StringName) -> bool:
	if item_id.is_empty() or not _inventory.item_catalog.has_definition(item_id):
		return false
	var item := _inventory.item_catalog.get_definition(item_id)
	if item.equipment_type == null or not _inventory.item_catalog.has_equipment_type(HAMMER_EQUIPMENT_TYPE_ID):
		return false
	return item.equipment_type.is_or_inherits(_inventory.item_catalog.get_equipment_type(HAMMER_EQUIPMENT_TYPE_ID))

func _used_hammer_against_killer() -> bool:
	if _last_incoming_contact == null:
		return false
	return _hammer_targets.get(_last_incoming_contact.source_runtime_id, &"") == _last_incoming_contact.source_definition_id

func _on_projectile_outcome_committed(outcome: ProjectileOutcome) -> void:
	if outcome.damage_response == DamageAffinityDefinition.Response.RESISTANT:
		_resisted_targets[outcome.contact.target_runtime_id] = outcome.contact.target_definition_id

func _build_killer_affinity_tip() -> String:
	if _last_incoming_contact == null:
		return ""
	var runtime_id := _last_incoming_contact.source_runtime_id
	var definition_id := _last_incoming_contact.source_definition_id
	if _resisted_targets.get(runtime_id, &"") != definition_id or not _entity_catalog.has_definition(definition_id):
		return ""
	var definition := _entity_catalog.get_definition(definition_id)
	var weapon_suggestions := _get_weapon_suggestions(definition)
	if weapon_suggestions.is_empty():
		return ""
	var sentence := DamageAffinityTextFormatter.build_enemy_sentence(definition, "Tip: ", false)
	return "%s %s" % [sentence, weapon_suggestions[_rng.randi_range(0, weapon_suggestions.size() - 1)]]

func _get_weapon_suggestions(definition: EntityDefinition) -> Array[String]:
	var preferred_types := DamageAffinityTextFormatter.get_damage_type_ids(definition, DamageAffinityDefinition.Response.WEAK)
	if preferred_types.is_empty():
		var resisted_types := DamageAffinityTextFormatter.get_damage_type_ids(definition, DamageAffinityDefinition.Response.RESISTANT)
		for damage_type in DAMAGE_TYPE_ORDER:
			if damage_type not in resisted_types:
				preferred_types.append(damage_type)
	var suggestions: Array[String] = []
	for damage_type in preferred_types:
		match damage_type:
			&"blunt":
				suggestions.append("Try hitting them with a Hammer.")
			&"slash":
				suggestions.append("Try hitting them with a Sword.")
			&"pierce":
				suggestions.append("Try shooting them with an Arrow.")
	return suggestions

func _has_any_item(item_ids: Array[StringName]) -> bool:
	for index in range(mini(_inventory.get_size(), InventoryModel.FILLABLE_SIZE)):
		var stack := _inventory.get_slot(index)
		if stack != null and stack.item_id in item_ids:
			return true
	return false

func _has_equipped_armor() -> bool:
	for armor_slot in range(ArmorDefinition.SLOT_COUNT):
		if _inventory.get_equipped_armor(armor_slot) != null:
			return true
	return false
