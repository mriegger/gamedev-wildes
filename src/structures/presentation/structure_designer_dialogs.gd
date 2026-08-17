extends CanvasLayer
class_name StructureDesignerDialogs

signal open_state_changed(open: bool)
signal new_draft_requested(size: Vector3i)
signal discard_confirmed

@onready var _new_dialog: ConfirmationDialog = $NewDialog
@onready var _length: SpinBox = $NewDialog/Fields/LengthRow/Length
@onready var _width: SpinBox = $NewDialog/Fields/WidthRow/Width
@onready var _height: SpinBox = $NewDialog/Fields/HeightRow/Height
@onready var _discard_dialog: ConfirmationDialog = $DiscardDialog

var _active: Window

func _ready() -> void:
	_new_dialog.confirmed.connect(_on_new_confirmed)
	_discard_dialog.confirmed.connect(_on_discard_confirmed)
	for dialog in [_new_dialog, _discard_dialog]:
		dialog.canceled.connect(_on_dialog_closed)
		dialog.close_requested.connect(_on_dialog_closed)
	_set_dimensions(StructureDefinition.DEFAULT_SIZE, StructureDefinition.MAX_EXTENT)

func show_new_dialog() -> bool:
	if is_open():
		return false
	_set_dimensions(StructureDefinition.DEFAULT_SIZE, StructureDefinition.MAX_EXTENT)
	_show(_new_dialog)
	return true

func show_discard_dialog() -> bool:
	if is_open():
		return false
	_show(_discard_dialog)
	return true

func close_active() -> bool:
	if _active == null:
		return false
	_active.hide()
	_active = null
	open_state_changed.emit(false)
	return true

func is_open() -> bool:
	return _active != null and _active.visible

func _set_dimensions(size: Vector3i, maximum: Vector3i) -> void:
	_length.max_value = maximum.x
	_width.max_value = maximum.z
	_height.max_value = maximum.y
	_length.value = size.x
	_width.value = size.z
	_height.value = size.y

func _show(dialog: Window) -> void:
	_active = dialog
	dialog.popup_centered()
	open_state_changed.emit(true)

func _on_new_confirmed() -> void:
	var size := Vector3i(int(_length.value), int(_height.value), int(_width.value))
	_finish_dialog()
	new_draft_requested.emit(size)

func _on_discard_confirmed() -> void:
	_finish_dialog()
	discard_confirmed.emit()

func _on_dialog_closed() -> void:
	_finish_dialog()

func _finish_dialog() -> void:
	if _active != null:
		_active.hide()
	_active = null
	open_state_changed.emit(false)
