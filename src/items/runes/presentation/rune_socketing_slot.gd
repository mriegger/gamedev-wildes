extends Panel
class_name RuneSocketingSlot

signal inventory_stack_dropped(source_index: int)
signal unsocket_requested()

enum State {
	GEAR_EMPTY,
	GEAR_SELECTED,
	UNAVAILABLE,
	LOCKED,
	EMPTY,
	FILLED,
}

@onready var _icon: TextureRect = $Margin/Content/Icon as TextureRect
@onready var _title: Label = $Margin/Content/Title as Label
@onready var _detail: Label = $Margin/Content/Detail as Label

var _state: State = State.UNAVAILABLE
var _drop_validator: Callable

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	_apply_state_style()

func set_drop_validator(validator: Callable) -> void:
	assert(validator.is_valid())
	_drop_validator = validator

func present(state: State, texture: Texture2D, title: String, detail: String, color: Color = Color.WHITE) -> void:
	_state = state
	_icon.texture = texture
	_icon.visible = texture != null
	_title.text = title
	_title.add_theme_color_override(&"font_color", color)
	_detail.text = detail
	_apply_state_style()

func get_state() -> State:
	return _state

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var source_index := _get_source_index(data)
	return source_index >= 0 and _drop_validator.is_valid() and bool(_drop_validator.call(source_index))

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var source_index := _get_source_index(data)
	if source_index >= 0 and _drop_validator.is_valid() and bool(_drop_validator.call(source_index)):
		inventory_stack_dropped.emit(source_index)

func _gui_input(event: InputEvent) -> void:
	if _state != State.FILLED or not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed or (mouse_event.button_index != MOUSE_BUTTON_LEFT and mouse_event.button_index != MOUSE_BUTTON_RIGHT):
		return
	unsocket_requested.emit()
	get_viewport().set_input_as_handled()

func _get_source_index(data: Variant) -> int:
	if not data is Dictionary:
		return -1
	var payload := data as Dictionary
	if not payload.has("source_index") or not payload.has("drag_count"):
		return -1
	var source_index := int(payload.get("source_index", -1))
	var drag_count := int(payload.get("drag_count", 0))
	return source_index if drag_count > 0 else -1

func _apply_state_style() -> void:
	var background := Color(0.10, 0.12, 0.14, 0.48)
	var border := Color(1, 1, 1, 0.13)
	match _state:
		State.GEAR_SELECTED, State.FILLED:
			background = Color(0.18, 0.24, 0.21, 0.62)
			border = Color(0.62, 0.86, 0.69, 0.62)
		State.EMPTY, State.GEAR_EMPTY:
			border = Color(0.74, 0.78, 0.82, 0.34)
		State.LOCKED:
			background = Color(0.16, 0.13, 0.10, 0.48)
			border = Color(0.82, 0.64, 0.38, 0.38)
		State.UNAVAILABLE:
			background = Color(0.08, 0.09, 0.10, 0.30)
			border = Color(1, 1, 1, 0.07)
	add_theme_stylebox_override(&"panel", WildesStyle.make_panel(background, 8, border, 1))
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _state == State.FILLED else Control.CURSOR_ARROW
