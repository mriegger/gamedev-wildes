extends RefCounted
class_name EntityNavigationLimits

var _max_search_radius: int
var _max_search_nodes: int
var _max_searches_per_tick: int

func _init(p_max_search_radius: int, p_max_search_nodes: int, p_max_searches_per_tick: int):
	assert(p_max_search_radius > 0)
	assert(p_max_search_nodes > 0)
	assert(p_max_searches_per_tick > 0)
	_max_search_radius = p_max_search_radius
	_max_search_nodes = p_max_search_nodes
	_max_searches_per_tick = p_max_searches_per_tick

func get_max_search_radius() -> int:
	return _max_search_radius

func get_max_search_nodes() -> int:
	return _max_search_nodes

func get_max_searches_per_tick() -> int:
	return _max_searches_per_tick
