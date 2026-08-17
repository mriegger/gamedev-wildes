extends RefCounted
class_name StructureDesignerLifecycleSnapshot

var in_level: bool
var saving_was_suspended: bool
var world_was_suspended: bool
var entities_were_suspended: bool
var clock_was_paused: bool
var debug_panel_input_was_enabled: bool
var player_process_mode: Node.ProcessMode
var player_visible: bool
var camera_process_mode: Node.ProcessMode
var camera_visible: bool
var gameplay_camera_current: bool
var hud_process_mode: Node.ProcessMode
var hud_visible: bool
var level_interaction_process_mode: Node.ProcessMode
var entrance_visible: bool

func _init(
	p_in_level: bool,
	p_saving_was_suspended: bool,
	p_world_was_suspended: bool,
	p_entities_were_suspended: bool,
	p_clock_was_paused: bool,
	p_debug_panel_input_was_enabled: bool,
	p_player: Node3D,
	p_camera_rig: Node3D,
	p_gameplay_camera: Camera3D,
	p_hud: CanvasLayer,
	p_level_interaction: Node,
	p_entrance_visible: bool,
) -> void:
	in_level = p_in_level
	saving_was_suspended = p_saving_was_suspended
	world_was_suspended = p_world_was_suspended
	entities_were_suspended = p_entities_were_suspended
	clock_was_paused = p_clock_was_paused
	debug_panel_input_was_enabled = p_debug_panel_input_was_enabled
	player_process_mode = p_player.process_mode
	player_visible = p_player.visible
	camera_process_mode = p_camera_rig.process_mode
	camera_visible = p_camera_rig.visible
	gameplay_camera_current = p_gameplay_camera.current
	hud_process_mode = p_hud.process_mode
	hud_visible = p_hud.visible
	level_interaction_process_mode = p_level_interaction.process_mode
	entrance_visible = p_entrance_visible
