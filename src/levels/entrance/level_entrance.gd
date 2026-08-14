extends Node3D
class_name LevelEntrance

var interaction_position: Vector3

func setup(position: Vector3, spawn_position: Vector3, block_catalog: BlockCatalog, definition: LevelEntranceDefinition):
	assert(definition != null)
	global_position = position
	var toward_spawn := spawn_position - position
	toward_spawn.y = 0.0
	if absf(toward_spawn.x) > absf(toward_spawn.z):
		rotation.y = PI * 0.5
	interaction_position = position + toward_spawn.normalized() * 1.6
	_build_arch(block_catalog, definition)

func _build_arch(block_catalog: BlockCatalog, definition: LevelEntranceDefinition):
	var arch_material := _make_material(block_catalog.get_definition(definition.arch_block_id).side_texture)
	var door_material := _make_material(block_catalog.get_definition(definition.door_block_id).side_texture)
	_add_box(Vector3(0.65, 3.2, 0.75), Vector3(-1.05, 1.6, 0.0), arch_material)
	_add_box(Vector3(0.65, 3.2, 0.75), Vector3(1.05, 1.6, 0.0), arch_material)
	_add_box(Vector3(2.75, 0.7, 0.75), Vector3(0.0, 3.15, 0.0), arch_material)
	_add_box(Vector3(1.35, 2.45, 0.16), Vector3(0.0, 1.225, 0.0), door_material)

func _make_material(texture: Texture2D) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 0.9
	return material

func _add_box(size: Vector3, position: Vector3, material: Material):
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = position
	instance.material_override = material
	add_child(instance)
