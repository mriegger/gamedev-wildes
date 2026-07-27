extends Node3D
class_name Game

## Game - root, typed DI, one setup pass after WorldController initializes (no reflection, no double injection)

@onready var world_env_node: WorldEnvironment = $WorldEnvironment
@onready var world: WorldController = $World as WorldController
@onready var player: PlayerMotor = $Player as PlayerMotor
@onready var interactor: PlayerInteractor = $Player/Interactor as PlayerInteractor
@onready var targeting_view: TargetingView = $Player/TargetingView as TargetingView
@onready var camera_rig: CameraRig = $CameraRig as CameraRig
@onready var camera_3d: Camera3D = $CameraRig/Pitch/Camera3D as Camera3D
@onready var sun: DirectionalLight3D = $Sun as DirectionalLight3D
@onready var sun_fill: DirectionalLight3D = $SunFill as DirectionalLight3D
@onready var game_clock: GameClock = $GameClock as GameClock
@onready var day_night_values: DayNightValues = $DayNightValues as DayNightValues
@onready var debug_clock_panel: DebugClockPanel = $DebugClockPanel as DebugClockPanel
@onready var hud: HUD = $HUD as HUD
@onready var hotbar: Hotbar = $HUD/Hotbar as Hotbar

var inventory_model: InventoryModel = null


func _ready():
	print("[Wildes] Game ready - 1280x720 Compatibility")
	print("Controls: WASD move, Space jump, Q/E rotate, Wheel zoom, Left mine, Right place, 1-9 hotbar, = debug")

	inventory_model = InventoryModel.new(9, 99)
	inventory_model.setup_starter()

	# One typed setup pass after world controller initialized (world is first child, so voxel_model already exists)
	_setup_all()

	print("[Game] Systems initialized: World=%s Player=%s CameraRig=%s Sun=%s Clock=%s Values=%s HUD=%s Inv=%s" % [
		world != null, player != null, camera_rig != null, sun != null, game_clock != null, day_night_values != null, hud != null, inventory_model != null
	])


func _setup_all():
	player.setup(world, world.voxel_model, camera_rig, camera_3d, inventory_model)
	interactor.setup(world.voxel_model, camera_3d, camera_rig, player, inventory_model)
	targeting_view.setup(world, world.voxel_model, player, interactor, camera_3d)
	camera_rig.setup(player)

	world.torch_renderer.set_player_ref(player)

	day_night_values.setup(game_clock, sun, sun_fill, world_env_node, world.config)
	debug_clock_panel.inject(game_clock, day_night_values)

	hud.setup(player, inventory_model)
	hotbar.inventory_model = inventory_model

	var spawn_pos = world.voxel_model.get_spawn_position()
	if player.global_position == Vector3.ZERO or player.global_position.distance_to(spawn_pos) < 0.01:
		pass
	else:
		player.global_position = spawn_pos + Vector3(0, 0.1, 0)

	camera_rig.target_position = player.global_position
	camera_rig.global_position = player.global_position
	camera_rig.current_yaw_deg = camera_rig.target_yaw_deg
	camera_3d.current = true
