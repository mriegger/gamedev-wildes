extends SceneTree

const DEFAULT_SEQS: int = 50000
const DEFAULT_OPS: int = 20
const MAX_STACK_OPTIONS: Array = [1, 2, 5, 10, 32, 64, 99, 0, -1]
const VALID_TYPES: Array = [1, 2, 3, 4, 5, 6, 7, 8]

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _failures: int = 0
var _tests_run: int = 0
var _asserts: int = 0

func _init():
	var seqs: int = DEFAULT_SEQS
	var ops: int = DEFAULT_OPS
	var args: Array = OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--seqs="):
			seqs = int(a.split("=")[1])
		elif a.begins_with("--ops="):
			ops = int(a.split("=")[1])
	_rng.seed = 123456789
	var ok: bool = true
	ok = _run_edge_cases() and ok
	ok = _run_raw_throughput() and ok
	ok = _run_fuzz(seqs, ops) and ok
	ok = _run_add_batch_properties() and ok
	if ok and _failures == 0:
		print("ALL PASS | tests_run=%d asserts=%d" % [_tests_run, _asserts])
		quit(0)
	else:
		print("FAIL | failures=%d tests_run=%d asserts=%d" % [_failures, _tests_run, _asserts])
		quit(1)

func _compute_totals(inv: InventoryModel) -> Array:
	var arr: Array = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	for s in inv.slots:
		if s != null:
			var t: int = int(s["type"])
			if t >= 0 and t < arr.size():
				arr[t] = int(arr[t]) + int(s["count"])
	return arr

func _totals_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if int(a[i]) != int(b[i]):
			return false
	return true

func _slots_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		var sa = a[i]
		var sb = b[i]
		if sa == null and sb == null:
			continue
		if sa == null or sb == null:
			return false
		if sa["type"] != sb["type"]:
			return false
		if int(sa["count"]) != int(sb["count"]):
			return false
	return true

func _validate_inv(inv: InventoryModel, out_totals: Array) -> bool:
	for i in range(out_totals.size()):
		out_totals[i] = 0
	for i in range(inv.size):
		var s = inv.slots[i]
		if s == null:
			continue
		if not (s is Dictionary):
			return false
		if not s.has("type") or not s.has("count"):
			return false
		var cnt: int = int(s["count"])
		if cnt <= 0:
			return false
		if inv.max_stack > 0 and cnt > inv.max_stack:
			return false
		var t = s["type"]
		if t == null or t == BlockId.Type.AIR:
			return false
		if not inv.can_slot_accept_type(i, t):
			return false
		if int(t) >= 0 and int(t) < out_totals.size():
			out_totals[int(t)] = int(out_totals[int(t)]) + cnt
	return true

func _assert(cond: bool, msg: String) -> bool:
	_asserts += 1
	if not cond:
		_failures += 1
		print("ASSERT FAIL: %s" % msg)
		return false
	return true

func _make_random_inventory(rng: RandomNumberGenerator) -> InventoryModel:
	var ms: int = MAX_STACK_OPTIONS[rng.randi_range(0, MAX_STACK_OPTIONS.size() - 1)]
	var inv: InventoryModel = InventoryModel.new(InventoryModel.TOTAL_SIZE, ms)
	var batches: int = rng.randi_range(0, 6)
	for _b in range(batches):
		var batch: Array[int] = []
		var sz: int = rng.randi_range(0, 14)
		for _i in range(sz):
			var pick: int = rng.randi_range(0, 12)
			if pick < VALID_TYPES.size():
				batch.append(VALID_TYPES[pick])
			elif pick == 8:
				batch.append(BlockId.Type.AIR)
			elif pick == 9:
				batch.append(-1)
			else:
				batch.append(rng.randi_range(0, BlockId.Type.COUNT - 1))
		var _can: bool = inv.can_add_batch(batch)
		var _added: bool = inv.add_batch(batch)
		if _can != _added:
			_assert(false, "can_add_batch vs add_batch mismatch batch=%s can=%s added=%s" % [str(batch), str(_can), str(_added)])
	var direct_fills: int = rng.randi_range(0, 4)
	for _f in range(direct_fills):
		var idx: int = rng.randi_range(0, inv.size - 1)
		if rng.randf() < 0.5:
			inv.slots[idx] = null
		else:
			var t: int = VALID_TYPES[rng.randi_range(0, VALID_TYPES.size() - 1)]
			if inv.can_slot_accept_type(idx, t):
				var cnt: int
				if inv.max_stack <= 0:
					cnt = rng.randi_range(1, 200)
				else:
					cnt = rng.randi_range(1, inv.max_stack)
				inv.slots[idx] = {"type": t, "count": cnt}
			else:
				inv.slots[idx] = null
	var tmp: Array = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	if not _validate_inv(inv, tmp):
		for i in range(inv.size):
			var s = inv.slots[i]
			if s != null:
				var cnt2: int = int(s["count"]) if s is Dictionary and s.has("count") else -1
				if cnt2 <= 0 or (inv.max_stack > 0 and cnt2 > inv.max_stack) or not inv.can_slot_accept_type(i, s["type"] if s is Dictionary else null):
					inv.slots[i] = null
	return inv

func _run_edge_cases() -> bool:
	print("[edge] starting")
	_tests_run += 1
	var inv0: InventoryModel = InventoryModel.new()
	_assert(inv0.size == InventoryModel.TOTAL_SIZE, "default size")
	_assert(inv0.max_stack == InventoryModel.DEFAULT_MAX_STACK, "default max_stack")
	for i in range(inv0.size):
		_assert(inv0.slots[i] == null, "empty init slot %d null" % i)
	_assert(not inv0.can_handle_drop(0, 1, 1), "empty src cannot handle")
	_assert(inv0.handle_drop(0, 1, 1) == false, "empty handle_drop false")
	var before0: Array = inv0.slots.duplicate(true)
	inv0.handle_drop(0, 1, 1)
	_assert(_slots_equal(before0, inv0.slots), "empty handle_drop identity")
	var inv1: InventoryModel = InventoryModel.new()
	inv1.slots[0] = {"type": BlockId.Type.GRASS, "count": 10}
	inv1.slots[1] = null
	_assert(inv1.can_handle_drop(0, 1, 10) == true, "move full to empty")
	var c1: Array = _compute_totals(inv1)
	var b1: Array = inv1.slots.duplicate(true)
	var r1: bool = inv1.handle_drop(0, 1, 10)
	_assert(r1 == true, "handle_drop move full true")
	_assert(inv1.slots[0] == null, "src null after move")
	_assert(inv1.slots[1] != null and inv1.slots[1]["type"] == BlockId.Type.GRASS and inv1.slots[1]["count"] == 10, "dst has moved stack")
	var tmp1: Array = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	_assert(_validate_inv(inv1, tmp1), "validate after move")
	_assert(_totals_equal(c1, _compute_totals(inv1)), "conserved after move")
	_assert(not _slots_equal(b1, inv1.slots), "mutated after successful drop")
	var inv2: InventoryModel = InventoryModel.new()
	inv2.slots[0] = {"type": BlockId.Type.STONE, "count": 10}
	inv2.slots[5] = null
	_assert(inv2.can_handle_drop(0, 5, 3) == true, "split to empty")
	var c2: Array = _compute_totals(inv2)
	inv2.handle_drop(0, 5, 3)
	_assert(inv2.slots[0]["count"] == 7, "split src 7")
	_assert(inv2.slots[5]["count"] == 3, "split dst 3")
	_assert(_totals_equal(c2, _compute_totals(inv2)), "conserved split")
	var inv3: InventoryModel = InventoryModel.new()
	inv3.slots[0] = {"type": BlockId.Type.DIRT, "count": 5}
	inv3.slots[1] = {"type": BlockId.Type.DIRT, "count": 3}
	_assert(inv3.can_handle_drop(0, 1, 5) == true, "merge same type full src")
	var c3: Array = _compute_totals(inv3)
	inv3.handle_drop(0, 1, 5)
	_assert(inv3.slots[1]["count"] == 8, "merge dst 8")
	_assert(inv3.slots[0] == null, "merge src null")
	_assert(_totals_equal(c3, _compute_totals(inv3)), "conserved merge")
	var inv4: InventoryModel = InventoryModel.new(InventoryModel.TOTAL_SIZE, 99)
	inv4.slots[0] = {"type": BlockId.Type.SAND, "count": 10}
	inv4.slots[1] = {"type": BlockId.Type.SAND, "count": 95}
	_assert(inv4.can_handle_drop(0, 1, 10) == true, "merge overflow can")
	var c4: Array = _compute_totals(inv4)
	var b4: Array = inv4.slots.duplicate(true)
	var can4: bool = inv4.can_handle_drop(0, 1, 10)
	var ret4: bool = inv4.handle_drop(0, 1, 10)
	_assert(can4 == ret4, "can==ret overflow")
	_assert(inv4.slots[1]["count"] == 99, "dst capped 99")
	_assert(inv4.slots[0]["count"] == 6, "src remainder 6")
	_assert(_totals_equal(c4, _compute_totals(inv4)), "conserved overflow")
	var tmp4: Array = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	_assert(_validate_inv(inv4, tmp4), "validate overflow")
	_assert(not _slots_equal(b4, inv4.slots), "mutated overflow")
	var inv5: InventoryModel = InventoryModel.new()
	inv5.slots[0] = {"type": BlockId.Type.GRASS, "count": 4}
	inv5.slots[1] = {"type": BlockId.Type.STONE, "count": 6}
	_assert(inv5.can_handle_drop(0, 1, 4) == true, "swap full different type")
	var c5: Array = _compute_totals(inv5)
	inv5.handle_drop(0, 1, 4)
	_assert(inv5.slots[0]["type"] == BlockId.Type.STONE and inv5.slots[0]["count"] == 6, "swap src is stone")
	_assert(inv5.slots[1]["type"] == BlockId.Type.GRASS and inv5.slots[1]["count"] == 4, "swap dst is grass")
	_assert(_totals_equal(c5, _compute_totals(inv5)), "conserved swap")
	var inv6: InventoryModel = InventoryModel.new()
	inv6.slots[0] = {"type": BlockId.Type.GRASS, "count": 8}
	inv6.slots[1] = {"type": BlockId.Type.STONE, "count": 2}
	_assert(inv6.can_handle_drop(0, 1, 3) == false, "partial swap must fail")
	var b6: Array = inv6.slots.duplicate(true)
	var r6: bool = inv6.handle_drop(0, 1, 3)
	_assert(r6 == false, "partial swap handle false")
	_assert(_slots_equal(b6, inv6.slots), "partial swap identity")
	var inv7: InventoryModel = InventoryModel.new()
	inv7.slots[0] = {"type": BlockId.Type.TORCH, "count": 5}
	var equip_start: int = InventoryModel.HOTBAR_SIZE + InventoryModel.BACKPACK_SIZE
	for ei in range(equip_start, inv7.size):
		_assert(inv7.can_handle_drop(0, ei, 5) == false, "drop to equipment must fail idx %d" % ei)
		var be: Array = inv7.slots.duplicate(true)
		var re: bool = inv7.handle_drop(0, ei, 5)
		_assert(re == false, "handle to equipment false")
		_assert(_slots_equal(be, inv7.slots), "equipment identity")
	_assert(inv7.can_handle_drop(0, 0, 1) == false, "same index fail")
	_assert(inv7.handle_drop(0, 0, 1) == false, "same index handle false")
	_assert(inv7.can_handle_drop(-1, 1, 1) == false, "oob src -1")
	_assert(inv7.can_handle_drop(0, 999, 1) == false, "oob dst 999")
	_assert(inv7.can_handle_drop(0, 1, 0) == false, "drag 0 fail")
	_assert(inv7.can_handle_drop(0, 1, -1) == false, "drag -1 fail")
	_assert(inv7.can_handle_drop(0, 1, 99) == false, "drag > count fail")
	var be7: Array = inv7.slots.duplicate(true)
	inv7.handle_drop(0, 1, 0)
	_assert(_slots_equal(be7, inv7.slots), "invalid drag identity")
	var inv8: InventoryModel = InventoryModel.new(InventoryModel.TOTAL_SIZE, 10)
	inv8.slots[0] = {"type": BlockId.Type.LOG, "count": 10}
	inv8.slots[1] = {"type": BlockId.Type.LOG, "count": 10}
	_assert(inv8.can_handle_drop(0, 1, 5) == false, "full dst no space")
	var b8: Array = inv8.slots.duplicate(true)
	_assert(inv8.handle_drop(0, 1, 5) == false, "full dst handle false")
	_assert(_slots_equal(b8, inv8.slots), "full dst identity")
	var inv9: InventoryModel = InventoryModel.new(InventoryModel.TOTAL_SIZE, 0)
	inv9.slots[0] = {"type": BlockId.Type.LEAVES, "count": 500}
	inv9.slots[1] = {"type": BlockId.Type.LEAVES, "count": 400}
	_assert(inv9.can_handle_drop(0, 1, 100) == true, "unlimited merge can")
	inv9.handle_drop(0, 1, 100)
	_assert(inv9.slots[1]["count"] == 500, "unlimited merge dst 500")
	_assert(inv9.slots[0]["count"] == 400, "unlimited merge src 400")
	var inv10: InventoryModel = InventoryModel.new()
	inv10.slots[0] = {"type": BlockId.Type.AIR, "count": 5}
	_assert(not inv10.can_slot_accept_type(0, BlockId.Type.AIR), "AIR not accepted")
	var tmp10: Array = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	_assert(not _validate_inv(inv10, tmp10), "AIR occupied fails check")
	print("[edge] done failures=%d" % _failures)
	return _failures == 0

func _run_raw_throughput() -> bool:
	print("[perf] measuring raw model throughput")
	_tests_run += 1
	var rng2: RandomNumberGenerator = RandomNumberGenerator.new()
	rng2.seed = 987654321
	var inv: InventoryModel = InventoryModel.new()
	inv.slots[0] = {"type": BlockId.Type.GRASS, "count": 50}
	inv.slots[1] = {"type": BlockId.Type.STONE, "count": 50}
	inv.slots[2] = {"type": BlockId.Type.DIRT, "count": 50}
	var n: int = 300000
	var t0: int = Time.get_ticks_msec()
	for i in range(n):
		var src: int = rng2.randi_range(0, 2)
		var dst: int = rng2.randi_range(0, 2)
		if dst == src:
			dst = (dst + 1) % 3
		var drag: int = rng2.randi_range(1, 2)
		inv.can_handle_drop(src, dst, drag)
	var t1: int = Time.get_ticks_msec()
	var rate_can: float = float(n) / max(1, t1 - t0) * 1000.0
	t0 = Time.get_ticks_msec()
	for i in range(n):
		var src: int = rng2.randi_range(0, 2)
		var dst: int = rng2.randi_range(0, 2)
		if dst == src:
			dst = (dst + 1) % 3
		var drag: int = 1
		if inv.can_handle_drop(src, dst, drag):
			inv.handle_drop(src, dst, drag)
	var t2: int = Time.get_ticks_msec()
	var rate_both: float = float(n) / max(1, t2 - t0) * 1000.0
	print("[perf] can_handle_drop: %.0f ops/s (%.0f seq/s @1op/seq) | can+handle: %.0f ops/s" % [rate_can, rate_can, rate_both])
	_assert(rate_can > 50000, "raw throughput sanity")
	return _failures == 0

func _run_add_batch_properties() -> bool:
	print("[add_batch] starting")
	_tests_run += 1
	var local_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	local_rng.seed = 0x12345678
	for iter in range(5000):
		var ms: int = MAX_STACK_OPTIONS[local_rng.randi_range(0, MAX_STACK_OPTIONS.size() - 1)]
		var inv: InventoryModel = InventoryModel.new(InventoryModel.TOTAL_SIZE, ms)
		var batch: Array[int] = []
		var n: int = local_rng.randi_range(0, 20)
		for i in range(n):
			batch.append(local_rng.randi_range(-2, BlockId.Type.COUNT + 1))
		var before: Array = inv.slots.duplicate(true)
		var can: bool = inv.can_add_batch(batch)
		var ret: bool = inv.add_batch(batch)
		_assert(can == ret, "add_batch can==ret iter %d batch %s can %s ret %s" % [iter, str(batch), str(can), str(ret)])
		var mutated: bool = not _slots_equal(before, inv.slots)
		if batch.is_empty():
			_assert(not mutated, "add_batch empty not mutated iter %d" % iter)
		else:
			_assert(mutated == can, "add_batch mutated==can non-empty iter %d" % iter)
		if not can:
			_assert(not mutated, "add_batch not mutated when can false iter %d" % iter)
			_assert(_slots_equal(before, inv.slots), "add_batch identity when false iter %d" % iter)
		var tmp: Array = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
		_assert(_validate_inv(inv, tmp), "add_batch validate iter %d ms %d" % [iter, ms])
		if _failures > 0:
			print("[add_batch] failed at iter %d batch %s ms %d" % [iter, str(batch), ms])
			return false
	print("[add_batch] done")
	return true

func _run_fuzz(seq_count: int, ops_per_seq: int) -> bool:
	print("[fuzz] starting seqs=%d ops_per_seq=%d total_ops=%d seed=%d" % [seq_count, ops_per_seq, seq_count * ops_per_seq, _rng.seed])
	_tests_run += 1
	var t0: int = Time.get_ticks_msec()
	var total_ops: int = seq_count * ops_per_seq
	var checks: int = 0
	var tmp_initial: Array = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	var tmp_before: Array = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	var tmp_after: Array = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	var tmp_validate: Array = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	for seq_idx in range(seq_count):
		var inv: InventoryModel = _make_random_inventory(_rng)
		var initial_totals: Array = _compute_totals(inv)
		if not _validate_inv(inv, tmp_initial):
			_assert(false, "fuzz init validate seq %d" % seq_idx)
			print("init slots %s" % str(inv.slots))
			return false
		if not _totals_equal(tmp_initial, initial_totals):
			_assert(false, "fuzz init totals mismatch")
		for op_idx in range(ops_per_seq):
			var src: int
			var dst: int
			var drag: int
			if _rng.randf() < 0.06:
				src = _rng.randi_range(-5, inv.size + 4)
			else:
				src = _rng.randi_range(0, inv.size - 1)
			if _rng.randf() < 0.06:
				dst = _rng.randi_range(-5, inv.size + 4)
			else:
				dst = _rng.randi_range(0, inv.size - 1)
			if _rng.randf() < 0.35:
				src = dst
			var src_slot = null
			if src >= 0 and src < inv.size:
				src_slot = inv.slots[src]
			if src_slot != null:
				var coin: float = _rng.randf()
				if coin < 0.62:
					drag = _rng.randi_range(1, int(src_slot["count"]))
				elif coin < 0.75:
					drag = 0
				elif coin < 0.85:
					drag = -_rng.randi_range(1, 3)
				elif coin < 0.92:
					drag = int(src_slot["count"]) + _rng.randi_range(1, 5)
				else:
					drag = int(src_slot["count"])
			else:
				drag = _rng.randi_range(-2, 6)
			var before_slots: Array = inv.slots.duplicate(true)
			var before_totals: Array = _compute_totals(inv)
			var can: bool = inv.can_handle_drop(src, dst, drag)
			var ret: bool = inv.handle_drop(src, dst, drag)
			var after_totals: Array = _compute_totals(inv)
			var mutated: bool = not _slots_equal(before_slots, inv.slots)
			checks += 1
			if not _assert(can == ret, "can==ret seq %d op %d src %d dst %d drag %d can %s ret %s" % [seq_idx, op_idx, src, dst, drag, str(can), str(ret)]):
				print(" before %s" % str(before_slots))
				print(" after %s" % str(inv.slots))
				return false
			if not _assert(mutated == can, "mutated==can seq %d op %d src %d dst %d drag %d mutated %s can %s" % [seq_idx, op_idx, src, dst, drag, str(mutated), str(can)]):
				print(" before %s" % str(before_slots))
				print(" after %s" % str(inv.slots))
				return false
			if not can:
				if not _assert(_slots_equal(before_slots, inv.slots), "identity when can false seq %d op %d" % [seq_idx, op_idx]):
					return false
				if not _assert(_totals_equal(before_totals, after_totals), "totals identity when can false seq %d op %d" % [seq_idx, op_idx]):
					return false
			else:
				if not _assert(_totals_equal(before_totals, after_totals), "conserved after drop seq %d op %d src %d dst %d drag %d before %s after %s" % [seq_idx, op_idx, src, dst, drag, str(before_totals), str(after_totals)]):
					return false
			if not _validate_inv(inv, tmp_validate):
				_assert(false, "validate after drop seq %d op %d src %d dst %d drag %d max %d slots %s" % [seq_idx, op_idx, src, dst, drag, inv.max_stack, str(inv.slots)])
				return false
			if not _totals_equal(tmp_validate, after_totals):
				_assert(false, "validate totals mismatch seq %d op %d" % [seq_idx, op_idx])
				return false
			if not _assert(_totals_equal(initial_totals, after_totals), "sequence conservation seq %d op %d" % [seq_idx, op_idx]):
				print(" initial %s after %s" % [str(initial_totals), str(after_totals)])
				return false
			if _failures > 0:
				return false
		if seq_idx > 0 and seq_idx % 10000 == 0:
			var elapsed: int = Time.get_ticks_msec() - t0
			var done_ops: int = (seq_idx + 1) * ops_per_seq
			var rate: float = float(done_ops) / max(1, elapsed) * 1000.0
			print("[fuzz] progress %d/%d seqs %d ops elapsed %d ms rate %.0f ops/s" % [seq_idx, seq_count, done_ops, elapsed, rate])
	var elapsed_total: int = Time.get_ticks_msec() - t0
	var rate_total: float = float(total_ops) / max(1, elapsed_total) * 1000.0
	print("[fuzz] done seqs=%d ops=%d checks=%d elapsed=%d ms rate=%.0f ops/s (%.0f seq/s) failures=%d" % [seq_count, total_ops, checks, elapsed_total, rate_total, float(seq_count) / max(1, elapsed_total) * 1000.0, _failures])
	return _failures == 0
