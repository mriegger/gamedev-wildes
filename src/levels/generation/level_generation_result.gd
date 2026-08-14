extends RefCounted
class_name LevelGenerationResult

enum FailureCode {
	NONE,
	INVALID_CATALOG,
	UNKNOWN_LEVEL,
	SEARCH_LIMIT_REACHED,
	NO_LAYOUT,
	INVALID_LAYOUT,
}

var succeeded: bool = false
var failure_code: FailureCode = FailureCode.NONE
var failure_reason: String
var layout: LevelLayout

static func make_success(p_layout: LevelLayout) -> LevelGenerationResult:
	var result := LevelGenerationResult.new()
	result.succeeded = true
	result.layout = p_layout
	return result

static func make_failure(code: FailureCode, reason: String) -> LevelGenerationResult:
	var result := LevelGenerationResult.new()
	result.failure_code = code
	result.failure_reason = reason
	return result
