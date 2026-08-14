extends SceneTree

var _errors: Array[String] = []

func _init():
	var orphan_before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var vignette_scene := load("res://player/effects/player_hit_vignette.tscn") as PackedScene
	_expect(vignette_scene != null, "player hit vignette scene did not load")
	if vignette_scene == null:
		_finish(orphan_before)
		return
	var vignette := vignette_scene.instantiate() as PlayerHitVignette
	_expect(vignette != null, "player hit vignette did not instantiate")
	if vignette == null:
		_finish(orphan_before)
		return
	root.add_child(vignette)
	await process_frame
	_expect(not vignette.visible, "player hit vignette started visible")
	_expect(not vignette.is_processing(), "player hit vignette started processing")
	_expect(vignette.mouse_filter == Control.MOUSE_FILTER_IGNORE, "player hit vignette intercepts pointer input")
	_expect(is_zero_approx(vignette.get_intensity()), "player hit vignette started with intensity")
	vignette.play()
	_expect(vignette.visible, "player hit vignette did not become visible")
	_expect(vignette.is_processing(), "player hit vignette did not start processing")
	_expect(is_equal_approx(vignette.get_intensity(), 1.0), "player hit vignette did not start at full intensity")
	vignette._process(PlayerHitVignette.HOLD_SECONDS + PlayerHitVignette.FADE_SECONDS * 0.5)
	_expect(vignette.get_intensity() > 0.0 and vignette.get_intensity() < 1.0, "player hit vignette did not fade")
	vignette.play()
	_expect(is_equal_approx(vignette.get_intensity(), 1.0), "repeated hit did not restart player hit vignette")
	vignette._process(PlayerHitVignette.HOLD_SECONDS + PlayerHitVignette.FADE_SECONDS)
	_expect(not vignette.visible, "player hit vignette remained visible after its duration")
	_expect(not vignette.is_processing(), "player hit vignette kept processing after its duration")
	vignette.queue_free()
	await process_frame
	_finish(orphan_before)

func _expect(condition: bool, message: String):
	if not condition:
		_errors.append(message)

func _finish(orphan_before: int):
	var orphan_after := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_after <= orphan_before, "orphan count increased from %d to %d" % [orphan_before, orphan_after])
	if _errors.is_empty():
		print("PLAYER_HIT_VIGNETTE PASS orphan=%d" % orphan_after)
		quit(0)
	else:
		print("PLAYER_HIT_VIGNETTE FAIL %s" % str(_errors))
		quit(1)
