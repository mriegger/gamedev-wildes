extends EntityAnimationDriver
class_name BirdAnimationDriver

enum ColorVariant {
	CROW,
	REDBIRD,
	DUCK,
	BLUEBIRD,
	OWL,
}

const COLOR_PALETTES: Array[Dictionary] = [
	{&"body": Color(0.075, 0.09, 0.115), &"head": Color(0.055, 0.065, 0.085), &"wing": Color(0.025, 0.032, 0.045), &"beak": Color(0.16, 0.17, 0.18), &"leg": Color(0.12, 0.12, 0.13)},
	{&"body": Color(0.72, 0.12, 0.08), &"head": Color(0.78, 0.15, 0.1), &"wing": Color(0.34, 0.055, 0.045), &"beak": Color(0.82, 0.48, 0.12), &"leg": Color(0.4, 0.24, 0.14)},
	{&"body": Color(0.48, 0.31, 0.18), &"head": Color(0.08, 0.3, 0.2), &"wing": Color(0.27, 0.18, 0.12), &"beak": Color(0.86, 0.58, 0.12), &"leg": Color(0.75, 0.39, 0.1)},
	{&"body": Color(0.18, 0.43, 0.72), &"head": Color(0.22, 0.5, 0.8), &"wing": Color(0.08, 0.22, 0.45), &"beak": Color(0.25, 0.22, 0.18), &"leg": Color(0.34, 0.25, 0.18)},
	{&"body": Color(0.48, 0.36, 0.23), &"head": Color(0.7, 0.57, 0.36), &"wing": Color(0.3, 0.2, 0.12), &"beak": Color(0.9, 0.7, 0.2), &"leg": Color(0.45, 0.32, 0.18)},
]
const OWL_EYE_EMISSION_ENERGY: float = 0.675

var _rig_root: Node3D
var _body_pivot: Node3D
var _head_pivot: Node3D
var _left_wing_pivot: Node3D
var _right_wing_pivot: Node3D
var _tail_pivot: Node3D
var _left_leg_pivot: Node3D
var _right_leg_pivot: Node3D
var _body_mesh: MeshInstance3D
var _head_mesh: MeshInstance3D
var _beak_mesh: MeshInstance3D
var _left_eye_mesh: MeshInstance3D
var _right_eye_mesh: MeshInstance3D
var _tail_mesh: MeshInstance3D
var _wing_meshes: Array[MeshInstance3D] = []
var _leg_meshes: Array[MeshInstance3D] = []
var _wing_flap_audio: AudioStreamPlayer3D
var _elapsed: float = 0.0
var _wing_phase: float = 0.0
var _walk_phase: float = 0.0
var _rig_origin: Transform3D
var _body_origin: Transform3D
var _head_origin: Transform3D
var _left_wing_origin: Transform3D
var _right_wing_origin: Transform3D
var _tail_origin: Transform3D
var _left_leg_origin: Transform3D
var _right_leg_origin: Transform3D
var _beak_origin: Transform3D
var _call_elapsed: float = 0.0
var _audio_enabled: bool = true

func setup(p_actor: Node3D):
	super.setup(p_actor)
	var visual := get_parent() as Node3D
	assert(visual != null)
	_rig_root = visual.get_node(^"RigRoot") as Node3D
	_body_pivot = _rig_root.get_node(^"BodyPivot") as Node3D
	_head_pivot = _body_pivot.get_node(^"HeadAnchor/HeadPivot") as Node3D
	_left_wing_pivot = _body_pivot.get_node(^"LeftWingPivot") as Node3D
	_right_wing_pivot = _body_pivot.get_node(^"RightWingPivot") as Node3D
	_tail_pivot = _body_pivot.get_node(^"TailPivot") as Node3D
	_left_leg_pivot = _body_pivot.get_node(^"LeftLegPivot") as Node3D
	_right_leg_pivot = _body_pivot.get_node(^"RightLegPivot") as Node3D
	_body_mesh = _body_pivot.get_node(^"Body") as MeshInstance3D
	_head_mesh = _head_pivot.get_node(^"Head") as MeshInstance3D
	_beak_mesh = _head_pivot.get_node(^"Beak") as MeshInstance3D
	_left_eye_mesh = _head_pivot.get_node(^"LeftEye") as MeshInstance3D
	_right_eye_mesh = _head_pivot.get_node(^"RightEye") as MeshInstance3D
	_tail_mesh = _tail_pivot.get_node(^"Tail") as MeshInstance3D
	_wing_meshes.assign([
		_left_wing_pivot.get_node(^"LeftWing") as MeshInstance3D,
		_right_wing_pivot.get_node(^"RightWing") as MeshInstance3D,
	])
	_leg_meshes.assign([
		_left_leg_pivot.get_node(^"LeftLeg") as MeshInstance3D,
		_left_leg_pivot.get_node(^"LeftFoot") as MeshInstance3D,
		_right_leg_pivot.get_node(^"RightLeg") as MeshInstance3D,
		_right_leg_pivot.get_node(^"RightFoot") as MeshInstance3D,
	])
	_wing_flap_audio = visual.get_node(^"WingFlapAudio") as AudioStreamPlayer3D
	assert(_wing_flap_audio != null and _wing_flap_audio.stream != null)
	_rig_origin = _rig_root.transform
	_body_origin = _body_pivot.transform
	_head_origin = _head_pivot.transform
	_left_wing_origin = _left_wing_pivot.transform
	_right_wing_origin = _right_wing_pivot.transform
	_tail_origin = _tail_pivot.transform
	_left_leg_origin = _left_leg_pivot.transform
	_right_leg_origin = _right_leg_pivot.transform
	_beak_origin = _beak_mesh.transform

func apply_color_variant(variant: ColorVariant) -> void:
	assert(variant >= ColorVariant.CROW and variant <= ColorVariant.OWL)
	var palette := COLOR_PALETTES[variant]
	_apply_color(_body_mesh, palette[&"body"] as Color)
	_apply_color(_head_mesh, palette[&"head"] as Color)
	_apply_color(_beak_mesh, palette[&"beak"] as Color)
	_apply_color(_tail_mesh, palette[&"wing"] as Color)
	for wing_mesh in _wing_meshes:
		_apply_color(wing_mesh, palette[&"wing"] as Color)
	for leg_mesh in _leg_meshes:
		_apply_color(leg_mesh, palette[&"leg"] as Color)
	if variant == ColorVariant.OWL:
		_body_mesh.scale = Vector3(1.12, 1.15, 1.08)
		_head_mesh.scale = Vector3(1.35, 1.3, 1.08)
		_left_eye_mesh.scale = Vector3(2.2, 2.2, 1.4)
		_right_eye_mesh.scale = Vector3(2.2, 2.2, 1.4)
		_apply_emissive_color(_left_eye_mesh, Color(1.0, 0.72, 0.08))
		_apply_emissive_color(_right_eye_mesh, Color(1.0, 0.72, 0.08))

func set_audio_enabled(enabled: bool) -> void:
	_audio_enabled = enabled
	if not enabled and is_instance_valid(_wing_flap_audio):
		_wing_flap_audio.stop()

func advance(delta: float):
	assert(actor is BirdActor)
	_elapsed += delta
	_reset_pose()
	var bird := actor as BirdActor
	var wings_flapping := true
	match bird.brain.state:
		BirdBrain.State.CRUISE:
			_apply_flight(delta, 0.18, 55.0, -5.0)
		BirdBrain.State.DESCEND:
			_apply_flight(delta, 0.32, 68.0, 12.0)
		BirdBrain.State.GROUNDED_IDLE:
			wings_flapping = false
			_apply_idle()
			_apply_call(delta, bird.vocalizations != null and bird.vocalizations.playing)
		BirdBrain.State.GROUNDED_WALK:
			wings_flapping = false
			_apply_walk(delta)
		BirdBrain.State.TAKEOFF:
			_apply_flight(delta, 0.14, 70.0, -14.0)
	_update_wing_flap_audio(wings_flapping)

func _apply_call(delta: float, calling: bool) -> void:
	if not calling:
		_call_elapsed = 0.0
		return
	_call_elapsed += delta
	var pulse := absf(sin(_call_elapsed * TAU / 0.22))
	_head_pivot.position.z = _head_origin.origin.z + pulse * 0.045
	_head_pivot.rotation.x += pulse * deg_to_rad(9.0)
	_body_pivot.position.y += pulse * 0.012
	_beak_mesh.scale.y = 1.0 + pulse * 0.35

func _apply_flight(delta: float, cycle_seconds: float, amplitude_degrees: float, body_pitch_degrees: float) -> void:
	_wing_phase = fmod(_wing_phase + delta * TAU / cycle_seconds, TAU)
	var flap := sin(_wing_phase) * deg_to_rad(amplitude_degrees)
	_left_wing_pivot.rotation.z = _left_wing_origin.basis.get_euler().z + flap
	_right_wing_pivot.rotation.z = _right_wing_origin.basis.get_euler().z - flap
	_body_pivot.rotation.x = _body_origin.basis.get_euler().x + deg_to_rad(body_pitch_degrees)
	_rig_root.position.y = _rig_origin.origin.y + sin(_wing_phase * 2.0) * 0.018
	_left_leg_pivot.rotation.x = _left_leg_origin.basis.get_euler().x - deg_to_rad(24.0)
	_right_leg_pivot.rotation.x = _right_leg_origin.basis.get_euler().x - deg_to_rad(24.0)

func _apply_idle() -> void:
	_apply_folded_wings()
	_body_pivot.position.y = _body_origin.origin.y + sin(_elapsed * 2.2) * 0.008
	_head_pivot.rotation.y = _head_origin.basis.get_euler().y + sin(_elapsed * 0.8) * deg_to_rad(14.0)
	_head_pivot.rotation.x = _head_origin.basis.get_euler().x + sin(_elapsed * 1.3) * deg_to_rad(5.0)
	_tail_pivot.rotation.x = _tail_origin.basis.get_euler().x + sin(_elapsed * 3.7) * deg_to_rad(5.0)

func _apply_walk(delta: float) -> void:
	_apply_folded_wings()
	_walk_phase = fmod(_walk_phase + delta * TAU / 0.42, TAU)
	var stride := sin(_walk_phase)
	_left_leg_pivot.rotation.x = _left_leg_origin.basis.get_euler().x + stride * deg_to_rad(28.0)
	_right_leg_pivot.rotation.x = _right_leg_origin.basis.get_euler().x - stride * deg_to_rad(28.0)
	_body_pivot.position.y = _body_origin.origin.y + absf(stride) * 0.025
	_head_pivot.rotation.x = _head_origin.basis.get_euler().x - stride * deg_to_rad(4.0)

func _apply_folded_wings() -> void:
	_left_wing_pivot.rotation.y = _left_wing_origin.basis.get_euler().y - deg_to_rad(72.0)
	_right_wing_pivot.rotation.y = _right_wing_origin.basis.get_euler().y + deg_to_rad(72.0)

func _update_wing_flap_audio(wings_flapping: bool) -> void:
	if not _audio_enabled:
		if _wing_flap_audio.playing:
			_wing_flap_audio.stop()
		return
	if wings_flapping:
		if not _wing_flap_audio.playing:
			_wing_flap_audio.play()
	else:
		stop_flight_audio()

func stop_flight_audio() -> void:
	if _wing_flap_audio.playing:
		_wing_flap_audio.stop()

func _apply_color(mesh_instance: MeshInstance3D, color: Color) -> void:
	assert(mesh_instance != null and mesh_instance.mesh != null and mesh_instance.mesh.get_surface_count() > 0)
	var source := mesh_instance.mesh.surface_get_material(0) as StandardMaterial3D
	assert(source != null)
	var material := source.duplicate() as StandardMaterial3D
	material.albedo_color = color
	mesh_instance.material_override = material

func _apply_emissive_color(mesh_instance: MeshInstance3D, color: Color) -> void:
	_apply_color(mesh_instance, color)
	var material := mesh_instance.material_override as StandardMaterial3D
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = OWL_EYE_EMISSION_ENERGY

func _reset_pose() -> void:
	_rig_root.transform = _rig_origin
	_body_pivot.transform = _body_origin
	_head_pivot.transform = _head_origin
	_left_wing_pivot.transform = _left_wing_origin
	_right_wing_pivot.transform = _right_wing_origin
	_tail_pivot.transform = _tail_origin
	_left_leg_pivot.transform = _left_leg_origin
	_right_leg_pivot.transform = _right_leg_origin
	_beak_mesh.transform = _beak_origin
