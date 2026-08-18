extends EntityAnimationDriver
class_name BirdAnimationDriver

var _rig_root: Node3D
var _body_pivot: Node3D
var _head_pivot: Node3D
var _left_wing_pivot: Node3D
var _right_wing_pivot: Node3D
var _tail_pivot: Node3D
var _left_leg_pivot: Node3D
var _right_leg_pivot: Node3D
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
	_rig_origin = _rig_root.transform
	_body_origin = _body_pivot.transform
	_head_origin = _head_pivot.transform
	_left_wing_origin = _left_wing_pivot.transform
	_right_wing_origin = _right_wing_pivot.transform
	_tail_origin = _tail_pivot.transform
	_left_leg_origin = _left_leg_pivot.transform
	_right_leg_origin = _right_leg_pivot.transform

func advance(delta: float):
	assert(actor is BirdActor)
	_elapsed += delta
	_reset_pose()
	var bird := actor as BirdActor
	match bird.brain.state:
		BirdBrain.State.CRUISE:
			_apply_flight(delta, 0.18, 55.0, -5.0)
		BirdBrain.State.DESCEND:
			_apply_flight(delta, 0.32, 68.0, 12.0)
		BirdBrain.State.GROUNDED_IDLE:
			_apply_idle()
		BirdBrain.State.GROUNDED_WALK:
			_apply_walk(delta)
		BirdBrain.State.TAKEOFF:
			_apply_flight(delta, 0.14, 70.0, -14.0)

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

func _reset_pose() -> void:
	_rig_root.transform = _rig_origin
	_body_pivot.transform = _body_origin
	_head_pivot.transform = _head_origin
	_left_wing_pivot.transform = _left_wing_origin
	_right_wing_pivot.transform = _right_wing_origin
	_tail_pivot.transform = _tail_origin
	_left_leg_pivot.transform = _left_leg_origin
	_right_leg_pivot.transform = _right_leg_origin
