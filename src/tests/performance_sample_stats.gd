extends RefCounted

static func summarize(samples_usec: Array[int]) -> Dictionary:
	assert(not samples_usec.is_empty())
	var sorted_samples: Array[int] = samples_usec.duplicate()
	sorted_samples.sort()
	var total_usec: int = 0
	for sample_usec in sorted_samples:
		total_usec += sample_usec
	return {
		"sample_count": sorted_samples.size(),
		"mean_ms": float(total_usec) / float(sorted_samples.size()) / 1000.0,
		"p50_ms": _percentile_ms(sorted_samples, 0.50),
		"p95_ms": _percentile_ms(sorted_samples, 0.95),
		"p99_ms": _percentile_ms(sorted_samples, 0.99),
		"max_ms": float(sorted_samples.back()) / 1000.0,
	}

static func _percentile_ms(sorted_samples: Array[int], percentile: float) -> float:
	var index := clampi(ceili(percentile * float(sorted_samples.size())) - 1, 0, sorted_samples.size() - 1)
	return float(sorted_samples[index]) / 1000.0
