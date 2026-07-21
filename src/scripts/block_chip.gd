extends MeshInstance3D

@export var lifetime: float = 0.85
var vel: Vector3 = Vector3.ZERO
var gravity: float = 18.0
var spin_axis: Vector3 = Vector3.UP
var spin_speed: float = 0.0

func _ready():
	spin_axis = Vector3(randf()-0.5, randf()-0.5, randf()-0.5).normalized()
	spin_speed = randf_range(3.0, 9.0)

func _process(delta):
	vel.y -= gravity * delta
	global_position += vel * delta
	rotate(spin_axis, delta * spin_speed)
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
	# fade out near end
	if lifetime < 0.25:
		var mat = material_override
		if mat is StandardMaterial3D:
			mat.albedo_color.a = clamp(lifetime / 0.25 * 0.9, 0.0, 0.9)
		elif mat is ShaderMaterial:
			# ignore
			pass
