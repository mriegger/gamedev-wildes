extends SceneTree

var _errors: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_attempts_and_queries()
	_test_prepared_completions()
	_test_snapshot_restore()
	_test_restore_rejections()
	call_deferred("_finish")

func _finish() -> void:
	if _errors.is_empty():
		print("DUNGEON_PROGRESS_STATE PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _test_attempts_and_queries() -> void:
	var state := DungeonProgressState.new()
	var observed_snapshots: Array[Dictionary] = []
	var state_ref: WeakRef = weakref(state)
	state.state_changed.connect(func() -> void:
		var active: DungeonProgressState = state_ref.get_ref()
		if active != null:
			observed_snapshots.append(active.snapshot())
	)
	_expect(state.begin_attempt(&"") == -1, "empty instance ID began an attempt")
	_expect(observed_snapshots.is_empty(), "rejected attempt emitted state_changed")
	_expect(state.begin_attempt(&"stone_story") == 0, "first attempt did not return index zero")
	_expect(state.begin_attempt(&"stone_story") == 1, "second attempt did not return index one")
	_expect(state.begin_attempt(&"farmable_cave") == 0, "independent instance did not start at index zero")
	_expect(observed_snapshots.size() == 3, "successful attempts did not emit once each")
	_expect(state.get_completion_count(&"stone_story") == 0, "new attempts changed completion count")
	_expect(not state.has_claimed_reward(&"stone_story", &"basic_rune_reward"), "new attempt claimed a reward")
	_expect(not state.has_claimed_reward(&"", &"basic_rune_reward"), "empty instance ID reported a reward claim")
	_expect(not state.has_claimed_reward(&"stone_story", &""), "empty reward ID reported a reward claim")

func _test_prepared_completions() -> void:
	var state := DungeonProgressState.new()
	var observations: Array[Dictionary] = []
	var state_ref: WeakRef = weakref(state)
	state.state_changed.connect(func() -> void:
		var active: DungeonProgressState = state_ref.get_ref()
		if active != null:
			observations.append(active.snapshot())
	)
	var empty_reward := state.prepare_completion(&"stone_story")
	_expect(empty_reward != null, "farmable completion was not prepared")
	_expect(state.can_commit_prepared_completion(empty_reward), "fresh farmable completion was not committable")
	_expect(state.commit_prepared_completion(empty_reward), "farmable completion did not commit")
	_expect(state.get_completion_count(&"stone_story") == 1, "farmable completion count did not increment")
	_expect(not state.can_commit_prepared_completion(empty_reward), "committed completion remained committable")
	_expect(not state.commit_prepared_completion(empty_reward), "completion committed twice")

	var reward := state.prepare_completion(&"stone_story", &"basic_rune_reward")
	_expect(reward != null and state.can_commit_prepared_completion(reward), "one-time reward completion was not prepared")
	var signal_count_before_silent_commit := observations.size()
	_expect(state._commit_prepared_completion(reward), "silent reward completion did not commit")
	_expect(observations.size() == signal_count_before_silent_commit, "silent reward completion emitted early")
	_expect(state.get_completion_count(&"stone_story") == 2, "silent reward completion did not increment count")
	_expect(state.has_claimed_reward(&"stone_story", &"basic_rune_reward"), "silent reward completion did not claim reward")
	_expect(not state.can_commit_prepared_completion(reward), "silently committed reward remained committable")
	_expect(state._notify_prepared_completion(reward), "silent reward completion did not notify")
	_expect(observations.size() == signal_count_before_silent_commit + 1, "reward completion did not notify exactly once")
	_expect(not state._notify_prepared_completion(reward), "reward completion notified twice")
	_expect(state.prepare_completion(&"stone_story", &"basic_rune_reward") == null, "claimed reward was prepared again")

	var atomic := state.prepare_completion(&"stone_story", &"second_reward")
	_expect(atomic != null and state.commit_prepared_completion(atomic), "second reward completion did not commit")
	var atomic_observation: Dictionary = observations.back()
	var observed_record := atomic_observation["instances"]["stone_story"] as Dictionary
	_expect(int(observed_record["completion_count"]) == 3, "completion signal observed an old count")
	_expect("second_reward" in observed_record["claimed_reward_ids"], "completion signal observed an unclaimed reward")

	var stale := state.prepare_completion(&"stone_story")
	_expect(stale != null, "stale completion fixture was not prepared")
	_expect(state.begin_attempt(&"another_instance") == 0, "stale completion mutation fixture failed")
	_expect(not state.can_commit_prepared_completion(stale), "revision-stale completion remained committable")
	_expect(not state._commit_prepared_completion(stale), "revision-stale completion committed")

	var foreign_state := DungeonProgressState.new()
	var foreign := state.prepare_completion(&"stone_story")
	_expect(foreign != null, "foreign completion fixture was not prepared")
	_expect(not foreign_state.can_commit_prepared_completion(foreign), "foreign state accepted a prepared completion")
	_expect(not foreign_state._commit_prepared_completion(foreign), "foreign state committed a prepared completion")
	_expect(state.prepare_completion(&"") == null, "empty instance completion was prepared")

func _test_snapshot_restore() -> void:
	var encoded := {
		"version": 1.0,
		"instances": {
			"zeta": {
				"next_attempt_index": 4.0,
				"completion_count": 2.0,
				"claimed_reward_ids": ["z_reward", "a_reward"],
			},
			"alpha": {
				"next_attempt_index": 1,
				"completion_count": 0,
				"claimed_reward_ids": [],
			},
		},
	}
	var state := DungeonProgressState.new()
	_expect(state.restore(encoded), "valid dungeon progress did not restore")
	_expect(state.begin_attempt(&"zeta") == 4, "restored next attempt index changed")
	_expect(state.get_completion_count(&"zeta") == 2, "restored completion count changed")
	_expect(state.has_claimed_reward(&"zeta", &"a_reward"), "restored reward claim was missing")
	var snapshot := state.snapshot()
	_expect(snapshot["instances"].keys() == ["alpha", "zeta"], "snapshot instance IDs were not deterministic")
	_expect(snapshot["instances"]["zeta"]["claimed_reward_ids"] == ["a_reward", "z_reward"], "snapshot reward IDs were not deterministic")
	var copy := snapshot.duplicate(true)
	copy["instances"]["zeta"]["claimed_reward_ids"].clear()
	_expect(state.has_claimed_reward(&"zeta", &"a_reward"), "snapshot exposed mutable reward state")

	var round_trip := DungeonProgressState.new()
	_expect(round_trip.restore(state.snapshot()), "canonical dungeon progress did not round-trip")
	_expect(round_trip.snapshot() == state.snapshot(), "dungeon progress round-trip changed the snapshot")
	var prepared_before_restore := state.prepare_completion(&"zeta")
	_expect(prepared_before_restore != null, "restore revision fixture was not prepared")
	_expect(state.restore(state.snapshot()), "same-value restore failed")
	_expect(not state.can_commit_prepared_completion(prepared_before_restore), "restore did not invalidate a prepared completion")

	var exhausted := DungeonProgressState.new()
	_expect(exhausted.restore({
		"version": 1,
		"instances": {
			"capped": {
				"next_attempt_index": DungeonProgressState.MAXIMUM_COUNTER_VALUE,
				"completion_count": DungeonProgressState.MAXIMUM_COUNTER_VALUE,
				"claimed_reward_ids": [],
			},
		},
	}), "maximum counters did not restore")
	_expect(exhausted.begin_attempt(&"capped") == -1, "maximum attempt counter overflowed")
	_expect(exhausted.prepare_completion(&"capped") == null, "maximum completion counter overflowed")

func _test_restore_rejections() -> void:
	var state := DungeonProgressState.new()
	_expect(state.begin_attempt(&"preserved") == 0, "restore rejection fixture failed")
	var valid_record := {
		"next_attempt_index": 1,
		"completion_count": 1,
		"claimed_reward_ids": ["reward"],
	}
	_expect_rejected_unchanged(state, null, "null snapshot restored")
	_expect_rejected_unchanged(state, {"version": 1}, "missing instances restored")
	_expect_rejected_unchanged(state, {"version": 1, "instances": {}, "extra": true}, "extra snapshot field restored")
	_expect_rejected_unchanged(state, {"version": 2, "instances": {}}, "future snapshot version restored")
	_expect_rejected_unchanged(state, {"version": 1.5, "instances": {}}, "fractional snapshot version restored")
	_expect_rejected_unchanged(state, {"version": true, "instances": {}}, "boolean snapshot version restored")
	_expect_rejected_unchanged(state, {"version": 1, "instances": []}, "non-dictionary instances restored")
	_expect_rejected_unchanged(state, {"version": 1, "instances": {"": valid_record}}, "empty instance ID restored")
	_expect_rejected_unchanged(state, {"version": 1, "instances": {"dungeon": []}}, "non-dictionary record restored")
	var missing_field := valid_record.duplicate(true)
	missing_field.erase("completion_count")
	_expect_rejected_unchanged(state, {"version": 1, "instances": {"dungeon": missing_field}}, "record missing completion count restored")
	var extra_field := valid_record.duplicate(true)
	extra_field["extra"] = true
	_expect_rejected_unchanged(state, {"version": 1, "instances": {"dungeon": extra_field}}, "record with extra field restored")
	var uncompleted_claim := valid_record.duplicate(true)
	uncompleted_claim["completion_count"] = 0
	_expect_rejected_unchanged(state, {"version": 1, "instances": {"dungeon": uncompleted_claim}}, "reward claim without a completion restored")
	for invalid_counter in [-1, 0.5, DungeonProgressState.MAXIMUM_COUNTER_VALUE + 1, INF, true, "1"]:
		var invalid_attempt := valid_record.duplicate(true)
		invalid_attempt["next_attempt_index"] = invalid_counter
		_expect_rejected_unchanged(state, {"version": 1, "instances": {"dungeon": invalid_attempt}}, "invalid attempt counter restored")
		var invalid_completion := valid_record.duplicate(true)
		invalid_completion["completion_count"] = invalid_counter
		_expect_rejected_unchanged(state, {"version": 1, "instances": {"dungeon": invalid_completion}}, "invalid completion counter restored")
	for invalid_rewards in [null, {}, [1], [""], ["reward", "reward"]]:
		var invalid_reward_record := valid_record.duplicate(true)
		invalid_reward_record["claimed_reward_ids"] = invalid_rewards
		_expect_rejected_unchanged(state, {"version": 1, "instances": {"dungeon": invalid_reward_record}}, "invalid claimed rewards restored")

func _expect_rejected_unchanged(state: DungeonProgressState, encoded: Variant, message: String) -> void:
	var before := state.snapshot()
	_expect(not state.restore(encoded), message)
	_expect(state.snapshot() == before, "%s and changed live state" % message)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
