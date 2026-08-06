extends CanvasLayer
class_name AnimationTuningPanel

const EXPORT_PATH: String = "res://../player_animation_values.json"

@onready var panel: Panel = $Panel
@onready var close_button: Button = $Panel/VBox/Header/CloseButton
@onready var preview_selector: OptionButton = $Panel/VBox/PreviewRow/PreviewSelector
@onready var movement_grid: GridContainer = $Panel/VBox/Tabs/Movement/Scroll/VBox/Grid
@onready var animation_grid: GridContainer = $Panel/VBox/Tabs/Animation/Scroll/VBox/Grid
@onready var part_selector: OptionButton = $Panel/VBox/Tabs/Parts/VBox/PartSelector
@onready var position_x: SpinBox = $Panel/VBox/Tabs/Parts/VBox/TransformGrid/PositionX
@onready var position_y: SpinBox = $Panel/VBox/Tabs/Parts/VBox/TransformGrid/PositionY
@onready var position_z: SpinBox = $Panel/VBox/Tabs/Parts/VBox/TransformGrid/PositionZ
@onready var rotation_x: SpinBox = $Panel/VBox/Tabs/Parts/VBox/TransformGrid/RotationX
@onready var rotation_y: SpinBox = $Panel/VBox/Tabs/Parts/VBox/TransformGrid/RotationY
@onready var rotation_z: SpinBox = $Panel/VBox/Tabs/Parts/VBox/TransformGrid/RotationZ
@onready var scale_x: SpinBox = $Panel/VBox/Tabs/Parts/VBox/TransformGrid/ScaleX
@onready var scale_y: SpinBox = $Panel/VBox/Tabs/Parts/VBox/TransformGrid/ScaleY
@onready var scale_z: SpinBox = $Panel/VBox/Tabs/Parts/VBox/TransformGrid/ScaleZ
@onready var reset_button: Button = $Panel/VBox/Footer/ResetButton
@onready var export_button: Button = $Panel/VBox/Footer/ExportButton
@onready var status_label: Label = $Panel/VBox/StatusLabel

var _motor: PlayerMotor
var _driver: PlayerAnimationDriver
var _animator: BlockyHumanoidAnimator
var _movement_defaults: Dictionary = {}
var _animation_defaults: Dictionary = {}
var _numeric_controls: Dictionary = {}
var _part_spins: Array[SpinBox] = []
var _syncing: bool = false

func _ready():
	panel.add_theme_stylebox_override("panel", WildesStyle.make_panel(Color(0.06, 0.07, 0.09, 0.96), 10, Color(0.55, 0.68, 0.82, 0.72), 1))
	_part_spins = [position_x, position_y, position_z, rotation_x, rotation_y, rotation_z, scale_x, scale_y, scale_z]
	for spin in _part_spins:
		spin.value_changed.connect(_on_part_value_changed)
	close_button.pressed.connect(hide_panel)
	preview_selector.item_selected.connect(_on_preview_selected)
	part_selector.item_selected.connect(_on_part_selected)
	reset_button.pressed.connect(_on_reset_pressed)
	export_button.pressed.connect(_on_export_pressed)

func setup(p_motor: PlayerMotor):
	_motor = p_motor
	_driver = p_motor.animation_driver
	_animator = _driver.animator
	_animator.profile = _animator.profile.duplicate(true) as BlockyHumanoidAnimationProfile
	_movement_defaults = _capture_numeric_values(_motor)
	_animation_defaults = _capture_numeric_values(_animator.profile)
	_build_numeric_controls(_motor, movement_grid, &"character")
	_build_numeric_controls(_animator.profile, animation_grid, &"animation")
	for preview_state in _driver.get_preview_states():
		preview_selector.add_item(String(preview_state))
	for part in _animator.get_tuning_parts():
		part_selector.add_item(String(part))
	_sync_part_controls()
	status_label.text = "F10 toggles this panel. Changes apply immediately."

func is_open() -> bool:
	return visible

func show_panel():
	visible = true

func hide_panel():
	visible = false
	preview_selector.select(0)
	_driver.set_preview_state(PlayerAnimationDriver.PREVIEW_LIVE)

func toggle_panel():
	if visible:
		hide_panel()
	else:
		show_panel()

func export_values_to_path(path: String) -> Error:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(_build_export_data(), "\t", true, true))
	return OK

func _build_numeric_controls(source: Object, grid: GridContainer, group: StringName):
	for property in _numeric_properties(source):
		var property_name = property["name"] as StringName
		var label = Label.new()
		label.text = String(property_name).capitalize()
		label.custom_minimum_size.x = 190.0
		grid.add_child(label)
		var spin = SpinBox.new()
		spin.name = "%s__%s" % [String(group), String(property_name)]
		spin.custom_minimum_size = Vector2(140.0, 30.0)
		_configure_numeric_control(spin, property, float(source.get(property_name)))
		spin.value = float(source.get(property_name))
		spin.value_changed.connect(_on_numeric_value_changed.bind(group, property_name))
		grid.add_child(spin)
		_numeric_controls["%s.%s" % [String(group), String(property_name)]] = spin

func _configure_numeric_control(spin: SpinBox, property: Dictionary, current_value: float):
	spin.step = 0.001
	var hint = int(property["hint"])
	var hint_string = String(property["hint_string"])
	if hint == PROPERTY_HINT_RANGE and not hint_string.is_empty():
		var range_parts = hint_string.split(",")
		spin.min_value = float(range_parts[0])
		spin.max_value = float(range_parts[1])
		if range_parts.size() > 2 and range_parts[2].is_valid_float():
			spin.step = float(range_parts[2])
		spin.allow_greater = false
		spin.allow_lesser = false
	else:
		var property_name = String(property["name"])
		if property_name.ends_with("degrees"):
			spin.min_value = -180.0
			spin.max_value = 180.0
			spin.allow_lesser = true
		else:
			spin.min_value = 0.01 if property_name.ends_with("seconds") else 0.0
			spin.max_value = max(abs(current_value) * 4.0, 1.0)
			spin.allow_lesser = false
		spin.allow_greater = true

func _numeric_properties(source: Object) -> Array[Dictionary]:
	var properties: Array[Dictionary] = []
	for property in source.get_property_list():
		var usage = int(property["usage"])
		var type = int(property["type"])
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE and usage & PROPERTY_USAGE_EDITOR and type == TYPE_FLOAT:
			properties.append(property)
	return properties

func _capture_numeric_values(source: Object) -> Dictionary:
	var values: Dictionary = {}
	for property in _numeric_properties(source):
		var property_name = property["name"] as StringName
		values[property_name] = source.get(property_name)
	return values

func _on_numeric_value_changed(value: float, group: StringName, property_name: StringName):
	var source: Object = _motor if group == &"character" else _animator.profile
	source.set(property_name, value)

func _on_preview_selected(index: int):
	_driver.set_preview_state(StringName(preview_selector.get_item_text(index)))

func _on_part_selected(_index: int):
	_sync_part_controls()

func _on_part_value_changed(_value: float):
	if _syncing:
		return
	var part = StringName(part_selector.get_item_text(part_selector.selected))
	_animator.set_tuning_transform(
		part,
		Vector3(position_x.value, position_y.value, position_z.value),
		Vector3(rotation_x.value, rotation_y.value, rotation_z.value),
		Vector3(scale_x.value, scale_y.value, scale_z.value)
	)

func _sync_part_controls():
	_syncing = true
	var part = StringName(part_selector.get_item_text(part_selector.selected))
	var transform = _animator.get_tuning_transform(part)
	var position = transform["position"] as Vector3
	var rotation_degrees = transform["rotation_degrees"] as Vector3
	var scale = transform["scale"] as Vector3
	position_x.value = position.x
	position_y.value = position.y
	position_z.value = position.z
	rotation_x.value = rotation_degrees.x
	rotation_y.value = rotation_degrees.y
	rotation_z.value = rotation_degrees.z
	scale_x.value = scale.x
	scale_y.value = scale.y
	scale_z.value = scale.z
	_syncing = false

func _on_reset_pressed():
	_restore_values(_motor, _movement_defaults, &"character")
	_restore_values(_animator.profile, _animation_defaults, &"animation")
	_animator.reset_tuning_transforms()
	_sync_part_controls()
	status_label.text = "All values reset to their startup defaults."

func _restore_values(source: Object, values: Dictionary, group: StringName):
	for property_name in values:
		source.set(property_name, values[property_name])
		var control = _numeric_controls["%s.%s" % [String(group), String(property_name)]] as SpinBox
		control.set_value_no_signal(float(values[property_name]))

func _on_export_pressed():
	var absolute_path = ProjectSettings.globalize_path(EXPORT_PATH)
	var error = export_values_to_path(absolute_path)
	status_label.text = "Exported %s" % absolute_path if error == OK else "Export failed: %s" % error_string(error)

func _build_export_data() -> Dictionary:
	var parts: Dictionary = {}
	for part in _animator.get_tuning_parts():
		var transform = _animator.get_tuning_transform(part)
		parts[String(part)] = {
			"position": _vector_to_array(transform["position"] as Vector3),
			"rotation_degrees": _vector_to_array(transform["rotation_degrees"] as Vector3),
			"scale": _vector_to_array(transform["scale"] as Vector3),
		}
	return {
		"format": "wildes_player_animation",
		"version": 1,
		"character": _capture_numeric_values(_motor),
		"animation": _capture_numeric_values(_animator.profile),
		"parts": parts,
	}

func _vector_to_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]
