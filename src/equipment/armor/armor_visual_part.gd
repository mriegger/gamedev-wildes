extends Resource
class_name ArmorVisualPart

enum Attachment {
	HEAD,
	TORSO,
	LEFT_ARM,
	RIGHT_ARM,
	LEFT_LEG,
	RIGHT_LEG,
	LEFT_FOOT,
	RIGHT_FOOT,
	COUNT,
}

@export var attachment: Attachment = Attachment.HEAD
@export var mesh: Mesh
@export var local_transform: Transform3D = Transform3D.IDENTITY

func validate(source: String) -> bool:
	var valid := true
	if attachment < Attachment.HEAD or attachment >= Attachment.COUNT:
		push_error("[ArmorVisualPart] Invalid attachment at %s" % source)
		valid = false
	if mesh == null:
		push_error("[ArmorVisualPart] Missing mesh at %s" % source)
		valid = false
	return valid
