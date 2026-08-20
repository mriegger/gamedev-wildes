extends RefCounted
class_name NavigationPriorityQueue

var _entries: Array = []
var _precedes: Callable

func _init(p_precedes: Callable) -> void:
	assert(p_precedes.is_valid())
	_precedes = p_precedes

func is_empty() -> bool:
	return _entries.is_empty()

func clear() -> void:
	_entries.clear()

func push(entry: Variant) -> void:
	_entries.append(entry)
	var index := _entries.size() - 1
	while index > 0:
		var parent := (index - 1) / 2
		if not bool(_precedes.call(_entries[index], _entries[parent])):
			break
		var parent_entry = _entries[parent]
		_entries[parent] = _entries[index]
		_entries[index] = parent_entry
		index = parent

func pop() -> Variant:
	assert(not _entries.is_empty())
	var first = _entries[0]
	var last = _entries.pop_back()
	if not _entries.is_empty():
		_entries[0] = last
		var index := 0
		while true:
			var left := index * 2 + 1
			var right := left + 1
			var smallest := index
			if left < _entries.size() and bool(_precedes.call(_entries[left], _entries[smallest])):
				smallest = left
			if right < _entries.size() and bool(_precedes.call(_entries[right], _entries[smallest])):
				smallest = right
			if smallest == index:
				break
			var smallest_entry = _entries[smallest]
			_entries[smallest] = _entries[index]
			_entries[index] = smallest_entry
			index = smallest
	return first
