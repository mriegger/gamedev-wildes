extends SceneTree

var _errors: Array[String] = []
var _consumed_item_ids: Array[StringName] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	_expect(item_catalog.validate(block_catalog), "item catalog rejected consumption content")
	var pumpkin := item_catalog.get_definition(&"pumpkin")
	var apple := item_catalog.get_definition(&"apple")
	var health_potion := item_catalog.get_definition(&"health_potion")
	var pumpkin_action := pumpkin.secondary_action as ConsumableActionDefinition
	var apple_action := apple.secondary_action as ConsumableActionDefinition
	var potion_action := health_potion.secondary_action as ConsumableActionDefinition
	_expect(pumpkin_action != null and is_equal_approx(pumpkin_action.health_restore_fraction, 0.1), "pumpkin does not restore ten percent health")
	_expect(apple_action != null and is_equal_approx(apple_action.health_restore_fraction, 0.1), "apple does not restore ten percent health")
	_expect(potion_action != null and is_equal_approx(potion_action.health_restore_fraction, 1.0), "health potion is not a full-health consumable")
	_expect(pumpkin.consume_audio != null and pumpkin.consume_audio.streams.size() == 1, "pumpkin munch audio is not configured")
	_expect(pumpkin.consume_audio.streams[0].resource_path == "res://assets/audio/sfx/items/consume/munch_crunchy_fruit_sequence_3x_CC0.wav", "pumpkin uses the wrong consume sound")
	_expect(health_potion.consume_audio != null and health_potion.consume_audio.streams.size() == 1, "health potion consume audio is not configured")

	var inventory := InventoryModel.new(item_catalog)
	inventory.slots[0] = InventoryStack.new(&"pumpkin", 2)
	var stats := ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	var max_health := stats.get_value(&"hp")
	var consumption := ItemConsumptionCoordinator.new()
	consumption.setup(inventory, stats)
	consumption.item_consumed.connect(_on_item_consumed)
	_expect(not consumption.can_consume_selected(), "full-health player could consume a pumpkin")
	_expect(not consumption.try_consume_selected(), "full-health consumption succeeded")
	_expect(inventory.get_slot(0).count == 2, "full-health consumption removed a pumpkin")

	stats.damage(75.0)
	var input_buffer := InputBuffer.new()
	var interactor := PlayerInteractor.new()
	interactor.inventory_model = inventory
	interactor._input_buffer = input_buffer
	interactor.item_consumption = consumption
	input_buffer.secondary_use_just = true
	input_buffer.secondary_use_pressed = true
	interactor._handle_item_actions(0.0)
	_expect(is_equal_approx(stats.current_hp, max_health * 0.35), "pumpkin did not restore ten percent health")
	_expect(inventory.get_slot(0).count == 1, "pumpkin consumption did not remove exactly one item")
	_expect(_consumed_item_ids == [&"pumpkin"], "pumpkin consumption did not announce one completed action")
	_expect(not input_buffer.secondary_use_just, "consumption left right-click available to placement")
	interactor._handle_item_actions(0.0)
	_expect(is_equal_approx(stats.current_hp, max_health * 0.35), "held right-click repeatedly consumed pumpkins")
	_expect(inventory.get_slot(0).count == 1, "held right-click removed another pumpkin")

	input_buffer.secondary_use_just = true
	interactor._handle_item_actions(0.0)
	_expect(is_equal_approx(stats.current_hp, max_health * 0.45), "second pumpkin did not restore ten percent health")
	_expect(inventory.get_slot(0) == null, "last consumed pumpkin left an empty stack")
	_expect(_consumed_item_ids == [&"pumpkin", &"pumpkin"], "second consumption did not announce completion")
	inventory.slots[0] = InventoryStack.new(&"apple", 1)
	input_buffer.secondary_use_just = true
	interactor._handle_item_actions(0.0)
	_expect(is_equal_approx(stats.current_hp, max_health * 0.55), "apple did not restore ten percent health")
	_expect(inventory.get_slot(0) == null, "consumed apple left an empty stack")
	_expect(_consumed_item_ids == [&"pumpkin", &"pumpkin", &"apple"], "apple consumption did not announce completion")
	interactor.free()

	var backpack_index := InventoryModel.HOTBAR_SIZE
	inventory.slots[backpack_index] = InventoryStack.new(&"health_potion", 1)
	stats.damage(25.0)
	var inventory_slot := (load("res://inventory/ui/inventory_slot.tscn") as PackedScene).instantiate() as InventorySlot
	root.add_child(inventory_slot)
	inventory_slot.set_slot_index(backpack_index)
	inventory_slot.set_item_consumption(consumption)
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	inventory_slot._gui_input(right_click)
	_expect(is_equal_approx(stats.current_hp, max_health), "right-clicking a backpack health potion did not restore full health")
	_expect(inventory.get_slot(backpack_index) == null, "right-clicking a backpack health potion did not consume it")
	_expect(_consumed_item_ids == [&"pumpkin", &"pumpkin", &"apple", &"health_potion"], "backpack consumption did not announce completion")
	inventory_slot.queue_free()
	await process_frame

	inventory.slots[0] = InventoryStack.new(&"health_potion", 1)
	stats.set_current_hp(0.0)
	_expect(not consumption.can_consume_selected(), "defeated player could consume a health potion")
	_expect(not consumption.try_consume_selected(), "defeated consumption succeeded")
	_expect(inventory.get_slot(0).count == 1, "defeated consumption removed a health potion")

	if _errors.is_empty():
		print("ITEM_CONSUMPTION PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _on_item_consumed(item_id: StringName) -> void:
	_consumed_item_ids.append(item_id)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
