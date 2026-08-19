extends RefCounted
class_name LootKeyedRandom

const DOMAIN: StringName = &"wildes-loot-v1"
const U53_RANGE: int = 1 << 53
const U53_MASK: int = U53_RANGE - 1

static func _digest_hex(
	seed: int,
	pool_id: StringName,
	path: Array[StringName],
	attempt: int = 0,
) -> String:
	return _digest(seed, pool_id, path, attempt).hex_encode()

static func unit(
	seed: int,
	pool_id: StringName,
	path: Array[StringName],
	attempt: int = 0,
) -> float:
	return float(u53(seed, pool_id, path, attempt)) / float(U53_RANGE)

static func u53(
	seed: int,
	pool_id: StringName,
	path: Array[StringName],
	attempt: int = 0,
) -> int:
	var digest := _digest(seed, pool_id, path, attempt)
	var value := 0
	for byte_index in range(7):
		value = (value << 8) | int(digest[byte_index])
	return value & U53_MASK

static func integer_inclusive(
	seed: int,
	pool_id: StringName,
	path: Array[StringName],
	minimum: int,
	maximum: int,
) -> int:
	assert(maximum >= minimum)
	var span := maximum - minimum + 1
	assert(span > 0 and span <= U53_RANGE)
	var acceptance_limit := U53_RANGE - (U53_RANGE % span)
	var rejection := 0
	while true:
		var attempt_path := path
		if rejection > 0:
			attempt_path = path.duplicate()
			attempt_path.append(&"rejection")
			attempt_path.append(StringName(str(rejection)))
		var value := u53(seed, pool_id, attempt_path)
		if value < acceptance_limit:
			return minimum + (value % span)
		rejection += 1
	return minimum

static func _digest(
	seed: int,
	pool_id: StringName,
	path: Array[StringName],
	attempt: int,
) -> PackedByteArray:
	assert(not pool_id.is_empty() and attempt >= 0)
	var fields: Array[String] = [String(DOMAIN), str(seed), String(pool_id)]
	for part in path:
		fields.append(String(part))
	fields.append("attempt")
	fields.append(str(attempt))
	var encoded := ""
	for field in fields:
		encoded += "%d:%s" % [field.to_utf8_buffer().size(), field]
	var context := HashingContext.new()
	var start_error := context.start(HashingContext.HASH_SHA256)
	assert(start_error == OK)
	var update_error := context.update(encoded.to_utf8_buffer())
	assert(update_error == OK)
	return context.finish()
