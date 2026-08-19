extends RefCounted

const OBSERVATION_SCRIPT_PATH: String = "res://entities/entity_target_observation.gd"

static func create(player_position: Vector3) -> Variant:
	if not ResourceLoader.exists(OBSERVATION_SCRIPT_PATH):
		return player_position
	var observation_script := load(OBSERVATION_SCRIPT_PATH) as Script
	assert(observation_script != null)
	return observation_script.new(
		player_position,
		player_position,
		Vector3.FORWARD,
		Vector3.RIGHT,
	)
