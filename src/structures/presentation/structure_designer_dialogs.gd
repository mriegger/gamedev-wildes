extends CanvasLayer
class_name StructureDesignerDialogs

signal open_state_changed(open: bool)
signal new_draft_requested(format: StructureDraft.Format, size: Vector3i)
signal import_requested(entry: StructureFileEntry)
signal export_id_requested(identifier: StringName)
signal overwrite_confirmed
signal discard_confirmed

@onready var _new_dialog: ConfirmationDialog = $NewDialog
@onready var _format: OptionButton = $NewDialog/Fields/Format
@onready var _length: SpinBox = $NewDialog/Fields/LengthRow/Length
@onready var _width: SpinBox = $NewDialog/Fields/WidthRow/Width
@onready var _height: SpinBox = $NewDialog/Fields/HeightRow/Height
@onready var _import_dialog: ConfirmationDialog = $ImportDialog
@onready var _import_list: ItemList = $ImportDialog/ImportList
@onready var _export_dialog: ConfirmationDialog = $ExportDialog
@onready var _identifier: LineEdit = $ExportDialog/Fields/Identifier
@onready var _overwrite_dialog: ConfirmationDialog = $OverwriteDialog
@onready var _discard_dialog: ConfirmationDialog = $DiscardDialog
@onready var _message_dialog: AcceptDialog = $MessageDialog

var _active: Window
var _entries: Array[StructureFileEntry] = []

func _ready() -> void:
	_format.add_item("Generic Structure", StructureDraft.Format.GENERIC_STRUCTURE)
	_format.add_item("Level Module", StructureDraft.Format.LEVEL_MODULE)
	_format.item_selected.connect(_on_format_selected)
	_new_dialog.confirmed.connect(_on_new_confirmed)
	_import_dialog.confirmed.connect(_on_import_confirmed)
	_export_dialog.confirmed.connect(_on_export_confirmed)
	_overwrite_dialog.confirmed.connect(_on_overwrite_confirmed)
	_discard_dialog.confirmed.connect(_on_discard_confirmed)
	_message_dialog.confirmed.connect(_on_dialog_closed)
	for dialog in [_new_dialog, _import_dialog, _export_dialog, _overwrite_dialog, _discard_dialog, _message_dialog]:
		dialog.canceled.connect(_on_dialog_closed)
		dialog.close_requested.connect(_on_dialog_closed)
	_on_format_selected(0)

func show_new_dialog() -> bool:
	if is_open():
		return false
	_format.select(0)
	_on_format_selected(0)
	_show(_new_dialog)
	return true

func show_import_dialog(entries: Array[StructureFileEntry]) -> bool:
	if is_open():
		return false
	_entries.assign(entries)
	_import_list.clear()
	for entry in _entries:
		var type_label := "Generic Structure" if entry.format == StructureDraft.Format.GENERIC_STRUCTURE else "Level Module"
		_import_list.add_item("%s — %s" % [entry.identifier, type_label])
	if not _entries.is_empty():
		_import_list.select(0)
	_show(_import_dialog)
	return true

func show_export_id_dialog() -> bool:
	if is_open():
		return false
	_identifier.clear()
	_show(_export_dialog)
	_identifier.call_deferred("grab_focus")
	return true

func show_overwrite_dialog(identifier: StringName) -> bool:
	if is_open():
		return false
	_overwrite_dialog.dialog_text = "Overwrite %s.tres with the current draft?" % identifier
	_show(_overwrite_dialog)
	return true

func show_discard_dialog() -> bool:
	if is_open():
		return false
	_show(_discard_dialog)
	return true

func show_message(title: String, message: String) -> void:
	if is_open():
		close_active()
	_message_dialog.title = title
	_message_dialog.dialog_text = message
	_show(_message_dialog)

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

func _on_format_selected(index: int) -> void:
	var format := _format.get_item_id(index) as StructureDraft.Format
	if format == StructureDraft.Format.GENERIC_STRUCTURE:
		_set_dimensions(StructureDefinition.DEFAULT_SIZE, StructureDefinition.MAX_EXTENT)
	else:
		_set_dimensions(StructureDraft.DEFAULT_LEVEL_MODULE_SIZE, LevelDefinition.HARD_MAX_EXTENT)

func _show(dialog: Window) -> void:
	_active = dialog
	dialog.popup_centered()
	open_state_changed.emit(true)

func _on_new_confirmed() -> void:
	var format := _format.get_selected_id() as StructureDraft.Format
	var size := Vector3i(int(_length.value), int(_height.value), int(_width.value))
	_finish_dialog()
	new_draft_requested.emit(format, size)

func _on_import_confirmed() -> void:
	var selected := _import_list.get_selected_items()
	if selected.is_empty():
		_finish_dialog()
		return
	var entry := _entries[selected[0]]
	_finish_dialog()
	import_requested.emit(entry)

func _on_export_confirmed() -> void:
	var value := StringName(_identifier.text.strip_edges())
	_finish_dialog()
	export_id_requested.emit(value)

func _on_overwrite_confirmed() -> void:
	_finish_dialog()
	overwrite_confirmed.emit()

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
