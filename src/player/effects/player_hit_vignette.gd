extends ColorRect
class_name PlayerHitVignette

const HOLD_SECONDS: float = 0.16
const FADE_SECONDS: float = 1.24

@onready var _shader_material: ShaderMaterial = material as ShaderMaterial

var _elapsed: float = HOLD_SECONDS + FADE_SECONDS

func _ready():
	_set_intensity(0.0)
	visible = false
	set_process(false)

func play():
	_elapsed = 0.0
	visible = true
	set_process(true)
	_set_intensity(1.0)

func _process(delta: float):
	_elapsed = minf(_elapsed + delta, HOLD_SECONDS + FADE_SECONDS)
	if _elapsed <= HOLD_SECONDS:
		return
	var remaining := 1.0 - (_elapsed - HOLD_SECONDS) / FADE_SECONDS
	_set_intensity(smoothstep(0.0, 1.0, remaining))
	if _elapsed >= HOLD_SECONDS + FADE_SECONDS:
		visible = false
		set_process(false)

func get_intensity() -> float:
	return float(_shader_material.get_shader_parameter(&"intensity"))

func _set_intensity(value: float):
	_shader_material.set_shader_parameter(&"intensity", clampf(value, 0.0, 1.0))
