extends Node
class_name StatModifierClock

var _stats: ActorStats

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

func setup(stats: ActorStats):
	_stats = stats
	set_process(true)

func _process(delta):
	_stats.advance_time(delta)
