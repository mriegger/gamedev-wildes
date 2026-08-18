@abstract
extends RefCounted
class_name InventoryTransferCoordinator

const PLAYER_SCOPE: StringName = &"player"

@abstract func get_inventory_stack(scope: StringName, index: int) -> InventoryStack
@abstract func get_socketed_rune_ids(scope: StringName, index: int) -> Array[StringName]
@abstract func can_handle_drop(source_scope: StringName, source_index: int, destination_scope: StringName, destination_index: int, drag_count: int) -> bool
@abstract func handle_drop(source_scope: StringName, source_index: int, destination_scope: StringName, destination_index: int, drag_count: int) -> bool
@abstract func quick_transfer(source_scope: StringName, source_index: int) -> bool
