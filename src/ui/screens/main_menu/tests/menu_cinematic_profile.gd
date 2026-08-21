extends SceneTree

var _errors: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var profile := load("res://ui/screens/main_menu/menu_cinematic_profile.tres") as MenuCinematicProfile
	var catalog := load("res://entities/entity_catalog.tres") as EntityCatalog
	_expect(profile != null, "cinematic profile did not load")
	_expect(catalog != null and catalog.validate(), "entity catalog did not load")
	if profile == null or catalog == null:
		_finish()
		return
	_expect(profile.validate(catalog), "cinematic profile validation failed")
	_expect(profile.world_seed == 1337, "cinematic seed changed")
	_expect(profile.shots.size() == 4, "cinematic does not contain four shots")
	_expect(is_equal_approx(profile.logo_delay_seconds, 0.5), "logo delay changed")
	_expect(is_equal_approx(profile.logo_fade_seconds, 1.5), "logo fade changed")
	_expect(is_equal_approx(profile.world_fade_seconds, 2.0), "world fade changed")
	_expect(is_equal_approx(profile.controls_fade_seconds, 2.0), "controls fade changed")
	var expected_shots := [
		{
			"id": &"sunrise_meadow",
			"time": 6.75,
			"anchor": Vector2i(0, 0),
			"yaw": 225.0,
			"pitch": -40.0,
			"size": 35.0,
			"drift": Vector2(4.0, 2.0),
			"spawns": [
				[&"sheep", 4, Vector2i(-5, 3), 5, 4101],
				[&"bird", 3, Vector2i(6, -4), 6, 4201],
			],
		},
		{
			"id": &"forest_water",
			"time": 12.5,
			"anchor": Vector2i(32, 22),
			"yaw": 135.0,
			"pitch": -43.0,
			"size": 42.0,
			"drift": Vector2(-5.0, 3.0),
			"spawns": [],
		},
		{
			"id": &"sunset_highland",
			"time": 18.0,
			"anchor": Vector2i(-34, 30),
			"yaw": 300.0,
			"pitch": -38.0,
			"size": 38.0,
			"drift": Vector2(5.0, -3.0),
			"spawns": [
				[&"slime_large", 1, Vector2i(-5, 2), 4, 4301],
				[&"stone_golem", 1, Vector2i(6, -2), 4, 4401],
			],
		},
		{
			"id": &"moonlit_vista",
			"time": 23.0,
			"anchor": Vector2i(34, -32),
			"yaw": 45.0,
			"pitch": -45.0,
			"size": 44.0,
			"drift": Vector2(-4.0, -2.0),
			"spawns": [
				[&"zombie", 2, Vector2i(-5, 3), 5, 4501],
				[&"skeleton", 2, Vector2i(5, 1), 5, 4601],
				[&"watcher", 1, Vector2i(0, -7), 4, 4701],
			],
		},
	]
	var expected_counts := {
		&"bird": 3,
		&"sheep": 4,
		&"slime_large": 1,
		&"stone_golem": 1,
		&"zombie": 2,
		&"skeleton": 2,
		&"watcher": 1,
	}
	var actual_counts: Dictionary = {}
	var behavior_seeds: Dictionary = {}
	for index in profile.shots.size():
		var shot := profile.shots[index]
		var expected := expected_shots[index] as Dictionary
		_expect(shot.id == expected["id"], "cinematic shot order changed at %d" % index)
		_expect(is_equal_approx(shot.duration_seconds, 10.0), "cinematic shot duration changed")
		_expect(is_equal_approx(shot.time_of_day, float(expected["time"])), "cinematic lighting time changed")
		_expect(shot.anchor == expected["anchor"], "cinematic anchor changed at %d" % index)
		_expect(is_equal_approx(shot.yaw_degrees, float(expected["yaw"])), "cinematic yaw changed at %d" % index)
		_expect(is_equal_approx(shot.pitch_degrees, float(expected["pitch"])), "cinematic pitch changed at %d" % index)
		_expect(is_equal_approx(shot.orthographic_size, float(expected["size"])), "cinematic size changed at %d" % index)
		_expect(shot.drift == expected["drift"], "cinematic drift changed at %d" % index)
		_expect(Vector2(shot.anchor).length() <= profile.maximum_anchor_radius, "cinematic anchor escaped its bounded region")
		var expected_spawns := expected["spawns"] as Array
		_expect(shot.spawns.size() == expected_spawns.size(), "cinematic spawn group count changed at %d" % index)
		for spawn_index in shot.spawns.size():
			var spawn := shot.spawns[spawn_index]
			var expected_spawn := expected_spawns[spawn_index] as Array
			_expect(spawn.entity_id == expected_spawn[0], "cinematic spawn entity changed")
			_expect(spawn.count == expected_spawn[1], "cinematic spawn count changed")
			_expect(spawn.column_offset == expected_spawn[2], "cinematic spawn offset changed")
			_expect(spawn.spread_radius == expected_spawn[3], "cinematic spawn radius changed")
			_expect(spawn.behavior_seed == expected_spawn[4], "cinematic spawn seed changed")
			actual_counts[spawn.entity_id] = int(actual_counts.get(spawn.entity_id, 0)) + spawn.count
			_expect(not behavior_seeds.has(spawn.behavior_seed), "cinematic behavior seed was reused")
			behavior_seeds[spawn.behavior_seed] = true
	_expect(actual_counts == expected_counts, "cinematic roster changed")
	var original_seed := profile.world_seed
	profile.world_seed = 0
	_expect(profile.validate(catalog), "cinematic profile rejected a noncanonical seed")
	profile.world_seed = original_seed
	var original_shots := profile.shots
	var one_shot: Array[MenuCinematicShot] = [profile.shots[0]]
	profile.shots = one_shot
	_expect(profile.validate(catalog), "cinematic profile rejected a nonempty noncanonical shot count")
	profile.shots = original_shots
	var original_duration := profile.shots[0].duration_seconds
	profile.shots[0].duration_seconds = 3.5
	_expect(profile.validate(catalog), "cinematic profile rejected a positive finite noncanonical shot duration")
	profile.shots[0].duration_seconds = 0.0
	_expect(not profile.validate(catalog), "cinematic profile accepted a zero shot duration")
	profile.shots[0].duration_seconds = INF
	_expect(not profile.validate(catalog), "cinematic profile accepted a non-finite shot duration")
	profile.shots[0].duration_seconds = original_duration
	profile.shots = []
	_expect(not profile.validate(catalog), "cinematic profile accepted an empty shot list")
	profile.shots = original_shots
	var original_second_id := profile.shots[1].id
	profile.shots[1].id = profile.shots[0].id
	_expect(not profile.validate(catalog), "cinematic profile accepted duplicate shot IDs")
	profile.shots[1].id = original_second_id
	var original_anchor := profile.shots[0].anchor
	profile.shots[0].anchor = Vector2i(1000, 1000)
	_expect(not profile.validate(catalog), "cinematic profile accepted an out-of-bounds shot anchor")
	profile.shots[0].anchor = original_anchor
	var original_pitch := profile.shots[0].pitch_degrees
	profile.shots[0].pitch_degrees = -80.0
	_expect(not profile.validate(catalog), "cinematic profile accepted an invalid camera pitch")
	profile.shots[0].pitch_degrees = original_pitch
	var original_entity_id := profile.shots[0].spawns[0].entity_id
	profile.shots[0].spawns[0].entity_id = &"missing_menu_entity"
	_expect(not profile.validate(catalog), "cinematic profile accepted an unknown entity ID")
	profile.shots[0].spawns[0].entity_id = original_entity_id
	var original_sheep_count := profile.shots[0].spawns[0].count
	profile.shots[0].spawns[0].count = 8
	_expect(not profile.validate(catalog), "cinematic profile accepted a roster above its population-cost bound")
	profile.shots[0].spawns[0].count = original_sheep_count
	_finish()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)

func _finish() -> void:
	if _errors.is_empty():
		print("MENU_CINEMATIC_PROFILE PASS")
		quit(0)
	else:
		for message in _errors:
			push_error(message)
		quit(1)
