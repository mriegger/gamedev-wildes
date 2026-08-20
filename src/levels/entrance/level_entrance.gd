extends Node3D
class_name LevelEntrance

const DOOR_OPEN_VOLUME_DB: float = -2.0

var interaction_position: Vector3
var _door_open_player: AudioStreamPlayer
var _door_open_streams: Array[AudioStream] = []
var _door_open_rng := RandomNumberGenerator.new()
var _last_door_open_index: int = -1

func setup(position: Vector3, spawn_position: Vector3, block_catalog: BlockCatalog, definition: LevelEntranceDefinition):
	assert(definition != null)
	assert(_door_open_player == null)
	global_position = position
	var toward_spawn := spawn_position - position
	toward_spawn.y = 0.0
	if absf(toward_spawn.x) > absf(toward_spawn.z):
		rotation.y = PI * 0.5
	interaction_position = position + toward_spawn.normalized() * 1.6
	_door_open_streams.assign(definition.door_open_streams)
	_door_open_rng.seed = String(definition.entrance_id).hash() ^ int(position.x * 73856093.0) ^ int(position.z * 19349663.0)
	_build_arch(block_catalog, definition)
	_build_audio()

func play_door_open_sound() -> void:
	assert(_door_open_player != null and not _door_open_streams.is_empty())
	var index := _door_open_rng.randi_range(0, _door_open_streams.size() - 1)
	if _door_open_streams.size() > 1 and index == _last_door_open_index:
		index = (index + 1 + _door_open_rng.randi_range(0, _door_open_streams.size() - 2)) % _door_open_streams.size()
	_last_door_open_index = index
	_door_open_player.stream = _door_open_streams[index]
	_door_open_player.play()

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

func _build_audio() -> void:
	_door_open_player = AudioStreamPlayer.new()
	_door_open_player.name = "DoorOpenSound"
	_door_open_player.volume_db = DOOR_OPEN_VOLUME_DB
	_door_open_player.bus = &"SFX"
	add_child(_door_open_player)
