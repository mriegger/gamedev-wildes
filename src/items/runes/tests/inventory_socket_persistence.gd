extends SceneTree

var _errors: Array[String] = []

func _init() -> void:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	_expect(block_catalog.validate(), "block catalog invalid")
	_expect(item_catalog.validate(block_catalog), "item catalog invalid")

	var inventory := InventoryModel.new(item_catalog)
	inventory.slots[0] = InventoryStack.new(&"copper_sword", 1)
	inventory.slots[1] = InventoryStack.new(&"copper_sword", 1)
	inventory.slots[2] = InventoryStack.new(&"basic_rune", 1)
	var empty_runes: Array[StringName] = []
	var one_rune: Array[StringName] = [&"basic_rune"]
	_expect(inventory.can_commit_socketed_rune(0, empty_runes, one_rune, 2, &"basic_rune"), "valid socket transaction rejected")
	_expect(inventory.commit_socketed_rune(0, empty_runes, one_rune, 2, &"basic_rune"), "valid socket transaction failed")
	_expect(inventory.get_slot(2) == null, "socket transaction did not consume one rune")
	_expect(inventory.get_socketed_rune_ids(0) == one_rune, "socket transaction did not update the target copy")
	_expect(inventory.get_socketed_rune_ids(1).is_empty(), "socket transaction changed another copy")
	var copied_ids := inventory.get_socketed_rune_ids(0)
	copied_ids.clear()
	_expect(inventory.get_socketed_rune_ids(0) == one_rune, "socket query exposed mutable state")
	_expect(not inventory.commit_socketed_rune(0, one_rune, empty_runes, 1, &"copper_sword"), "invalid replacement transaction succeeded")

	var backpack_index := InventoryModel.HOTBAR_SIZE
	_expect(inventory.handle_drop(0, backpack_index, 1), "socketed gear move failed")
	_expect(inventory.get_socketed_rune_ids(backpack_index) == one_rune, "gear move lost socket state")
	var encoded := inventory.to_dict()
	var decoded = JSON.parse_string(JSON.stringify(encoded))
	var restored := InventoryModel.new(item_catalog)
	_expect(decoded is Dictionary and restored.from_dict(decoded), "socketed inventory JSON round trip failed")
	_expect(restored.get_socketed_rune_ids(backpack_index) == one_rune, "socket state changed during restore")
	_expect(restored.get_socketed_rune_ids(1).is_empty(), "independent gear copy gained a socket during restore")

	var invalid_rune := encoded.duplicate(true)
	invalid_rune["regions"]["backpack"][0]["socketed_rune_ids"] = ["missing_rune"]
	var before_invalid_restore := restored.to_dict()
	_expect(not restored.from_dict(invalid_rune), "unknown socketed rune restored")
	_expect(restored.to_dict() == before_invalid_restore, "failed socket restore changed inventory")
	var trailing_empty := encoded.duplicate(true)
	trailing_empty["regions"]["backpack"][0]["socketed_rune_ids"] = ["basic_rune", ""]
	_expect(not restored.from_dict(trailing_empty), "non-canonical socket loadout restored")

	for index in range(InventoryModel.FILLABLE_SIZE):
		if index == backpack_index:
			continue
		restored.slots[index] = InventoryStack.new(&"dirt_block", 99)
	_expect(not restored.can_commit_unsocketed_rune(backpack_index, one_rune, empty_runes, &"basic_rune"), "unsocket succeeded without return capacity")
	_expect(restored.get_socketed_rune_ids(backpack_index) == one_rune, "failed unsocket changed gear")
	restored.slots[InventoryModel.HOTBAR_SIZE + 1] = null
	_expect(restored.commit_unsocketed_rune(backpack_index, one_rune, empty_runes, &"basic_rune"), "unsocket with return capacity failed")
	_expect(restored.get_socketed_rune_ids(backpack_index).is_empty(), "unsocket did not clear gear")
	_expect(restored.get_slot(InventoryModel.HOTBAR_SIZE + 1).item_id == &"basic_rune", "unsocket did not return the rune")

	var version_five_inventory := encoded.duplicate(true)
	for region_name in ["hotbar", "backpack", "equipment"]:
		for raw_stack in version_five_inventory["regions"][region_name]:
			if raw_stack is Dictionary:
				raw_stack.erase("socketed_rune_ids")
	var version_five_save := {"version": 5, "inventory": version_five_inventory}
	_expect(SaveManager._migrate_save_data(version_five_save), "version-five save did not migrate")
	_expect(version_five_save["version"] == SaveManager.CURRENT_SAVE_VERSION, "version-five save has the wrong migrated version")
	_expect(version_five_save["pumpkin_patch"] == {"present": false}, "version-five migration added a pumpkin patch")
	_expect(version_five_save["player_perks"] == {"allocations": {}}, "version-five migration chain did not initialize perks")
	_expect(version_five_save["apple_trees"] == AppleTreeState.new().snapshot(), "version-five migration added picked apples")
	for region_name in ["hotbar", "backpack", "equipment"]:
		for raw_stack in version_five_save["inventory"]["regions"][region_name]:
			if raw_stack is Dictionary:
				_expect(raw_stack["socketed_rune_ids"] == [], "migration did not initialize socket state")
	var version_four_save := {"version": 4, "inventory": version_five_inventory.duplicate(true)}
	_expect(SaveManager._migrate_save_data(version_four_save), "version-four migration chain failed")
	_expect(version_four_save["version"] == SaveManager.CURRENT_SAVE_VERSION and version_four_save["item_proficiency"] == {}, "version-four migration chain lost progression shape")
	_expect(version_four_save["pumpkin_patch"] == {"present": false}, "version-four migration added a pumpkin patch")
	_expect(version_four_save["player_perks"] == {"allocations": {}}, "version-four migration chain did not initialize perks")
	_expect(version_four_save["apple_trees"] == AppleTreeState.new().snapshot(), "version-four migration added picked apples")
	var version_eight_save := {"version": 8, "player_perks": {"allocations": {}}, "pumpkin_patch": {"present": false}}
	_expect(SaveManager._migrate_save_data(version_eight_save), "version-eight migration failed")
	_expect(version_eight_save["apple_trees"] == AppleTreeState.new().snapshot(), "version-eight migration added picked apples")
	var malformed_save := {"version": 5, "inventory": {"regions": {"hotbar": []}}}
	var malformed_before := malformed_save.duplicate(true)
	_expect(not SaveManager._migrate_save_data(malformed_save), "malformed version-five save migrated")
	_expect(malformed_save == malformed_before, "failed migration changed source data")

	if _errors.is_empty():
		print("INVENTORY_SOCKET_PERSISTENCE PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
