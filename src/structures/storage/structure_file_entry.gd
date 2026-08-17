extends RefCounted
class_name StructureFileEntry

var identifier: StringName:
	get:
		return _identifier
var absolute_path: String:
	get:
		return _absolute_path

var _identifier: StringName
var _absolute_path: String

func _init(p_identifier: StringName, p_absolute_path: String) -> void:
	_identifier = p_identifier
	_absolute_path = p_absolute_path
