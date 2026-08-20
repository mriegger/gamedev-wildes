@abstract
extends InventoryTransferCoordinator
class_name ChestTransferCoordinator

signal opened(position: Vector3i, definition: ContainerBlockDefinition)
signal closed
signal contents_changed(position: Vector3i)

const CHEST_SCOPE: StringName = &"chest"

@abstract func can_open(position: Vector3i) -> bool
@abstract func try_open(position: Vector3i, definition: ContainerBlockDefinition) -> bool
@abstract func close() -> void
@abstract func is_open() -> bool
@abstract func get_active_position() -> Variant
@abstract func move_all_to_backpack() -> bool
@abstract func has_items_to_take() -> bool
@abstract func is_active_one_time_reward() -> bool
