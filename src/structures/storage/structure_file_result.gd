extends RefCounted
class_name StructureFileResult

var succeeded: bool
var message: String
var draft: StructureDraft
var entry: StructureFileEntry

static func success(p_draft: StructureDraft, p_entry: StructureFileEntry) -> StructureFileResult:
	var result := StructureFileResult.new()
	result.succeeded = true
	result.draft = p_draft
	result.entry = p_entry
	return result

static func failure(p_message: String) -> StructureFileResult:
	var result := StructureFileResult.new()
	result.message = p_message
	return result
