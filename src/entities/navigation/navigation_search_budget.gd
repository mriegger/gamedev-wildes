extends RefCounted
class_name NavigationSearchBudget

var _max_searches: int
var _remaining_searches: int

func _init(max_searches: int):
	assert(max_searches > 0)
	_max_searches = max_searches
	_remaining_searches = max_searches

func reset():
	_remaining_searches = _max_searches

func try_acquire() -> bool:
	if _remaining_searches <= 0:
		return false
	_remaining_searches -= 1
	return true
