#!/usr/bin/env python3

import argparse
import json
import math
import statistics
from dataclasses import dataclass
from pathlib import Path
from typing import Any


RUN_COUNT = 3
RELATIVE_THRESHOLD = 0.15
REQUIRED_REGRESSION_PAIRS = 2


@dataclass(frozen=True)
class MetricPolicy:
    benchmark_id: str
    metric_id: str
    label: str
    noise_floor_ms: float | None
    budget_ms: float | None


METRIC_POLICIES = (
    MetricPolicy("game_performance", "steady_game_frame", "Steady gameplay CPU", 0.35, 6.0),
    MetricPolicy("game_performance", "streaming_game_frame", "Streaming gameplay CPU", 0.35, 8.33),
    MetricPolicy("game_performance", "chunk_build", "Worker-side chunk construction", 1.0, None),
    MetricPolicy("game_performance", "chunk_apply", "Main-thread chunk application", 0.25, 2.0),
    MetricPolicy("game_performance", "startup", "Game startup", None, None),
    MetricPolicy("game_performance", "streaming_queue_drain", "Streaming queue drain", None, None),
    MetricPolicy("entity_efficiency", "entity_frame", "Entity update", 0.25, 2.0),
    MetricPolicy("entity_efficiency", "bounded_path_search", "Bounded pathfinding", 1.0, 2.0),
    MetricPolicy("entity_efficiency", "spawn_frame", "Entity spawn", None, None),
    MetricPolicy("entity_efficiency", "preparation_frame", "Entity preparation", None, None),
)

REQUIRED_METRICS = {
    "entity_efficiency": {"entity_frame", "bounded_path_search", "spawn_frame", "preparation_frame"},
    "game_performance": {
        "steady_game_frame",
        "streaming_game_frame",
        "chunk_build",
        "chunk_apply",
        "startup",
        "streaming_queue_drain",
    },
}

SUMMARY_FIELDS = ("sample_count", "mean_ms", "p50_ms", "p95_ms", "p99_ms", "max_ms")


class AdvisoryArgumentParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        raise ValueError(message)


def _parser() -> argparse.ArgumentParser:
    parser = AdvisoryArgumentParser(description="Compare advisory Godot performance reports")
    parser.add_argument("--base-dir", required=True)
    parser.add_argument("--candidate-dir", required=True)
    parser.add_argument("--output-json", required=True)
    parser.add_argument("--summary", required=True)
    return parser


def _report_path(directory: Path, benchmark_id: str, run_number: int) -> Path:
    candidates = (
        directory / f"{benchmark_id}_{run_number}.json",
        directory / f"{benchmark_id}-{run_number}.json",
        directory / f"run_{run_number}" / f"{benchmark_id}.json",
        directory / f"run-{run_number}" / f"{benchmark_id}.json",
        directory / str(run_number) / f"{benchmark_id}.json",
    )
    return next((path for path in candidates if path.is_file()), candidates[0])


def _is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(float(value))


def _validate_summary(summary: Any) -> bool:
    if not isinstance(summary, dict):
        return False
    if not isinstance(summary.get("sample_count"), int) or summary["sample_count"] <= 0:
        return False
    for field in SUMMARY_FIELDS[1:]:
        value = summary.get(field)
        if not _is_number(value) or float(value) < 0.0:
            return False
    return True


def _load_report(path: Path, benchmark_id: str) -> tuple[dict[str, Any] | None, str | None]:
    if not path.is_file():
        return None, f"{path}: report is missing"
    try:
        report = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        return None, f"{path}: report could not be read: {error}"
    if not isinstance(report, dict):
        return None, f"{path}: report root must be an object"
    if not isinstance(report.get("schema_version"), int):
        return None, f"{path}: schema_version must be an integer"
    if report.get("benchmark_id") != benchmark_id:
        return None, f"{path}: benchmark_id must be {benchmark_id}"
    if not isinstance(report.get("workload"), dict):
        return None, f"{path}: workload must be an object"
    metrics = report.get("metrics")
    if not isinstance(metrics, dict):
        return None, f"{path}: metrics must be an object"
    for metric_id in REQUIRED_METRICS[benchmark_id]:
        if metric_id not in metrics:
            return None, f"{path}: required metric {metric_id} is missing"
        if not _validate_summary(metrics[metric_id]):
            return None, f"{path}: metric {metric_id} has an invalid summary"
    return report, None


def _load_series(directory: Path, benchmark_id: str, revision: str) -> tuple[list[dict[str, Any] | None], list[str]]:
    reports: list[dict[str, Any] | None] = []
    issues: list[str] = []
    for run_number in range(1, RUN_COUNT + 1):
        path = _report_path(directory, benchmark_id, run_number)
        report, issue = _load_report(path, benchmark_id)
        reports.append(report)
        if issue is not None:
            issues.append(f"{revision} {benchmark_id} run {run_number}: {issue}")
    reference = next((report for report in reports if report is not None), None)
    if reference is None:
        return reports, issues
    for index, report in enumerate(reports):
        if report is None:
            continue
        if report["schema_version"] != reference["schema_version"]:
            issues.append(f"{revision} {benchmark_id} run {index + 1}: schema does not match other {revision} runs")
            reports[index] = None
            continue
        if report["workload"] != reference["workload"]:
            issues.append(f"{revision} {benchmark_id} run {index + 1}: workload does not match other {revision} runs")
            reports[index] = None
    return reports, issues


def _matching_pairs(
    base_reports: list[dict[str, Any] | None],
    candidate_reports: list[dict[str, Any] | None],
    benchmark_id: str,
) -> tuple[list[tuple[int, dict[str, Any], dict[str, Any]]], list[str]]:
    pairs: list[tuple[int, dict[str, Any], dict[str, Any]]] = []
    issues: list[str] = []
    for index, (base, candidate) in enumerate(zip(base_reports, candidate_reports, strict=True)):
        if base is None or candidate is None:
            continue
        mismatches: list[str] = []
        if base["schema_version"] != candidate["schema_version"]:
            mismatches.append("schema")
        if base["benchmark_id"] != candidate["benchmark_id"]:
            mismatches.append("benchmark")
        if base["workload"] != candidate["workload"]:
            mismatches.append("workload")
        if mismatches:
            issues.append(
                f"{benchmark_id} run {index + 1}: base and head {'/'.join(mismatches)} do not match"
            )
            continue
        pairs.append((index + 1, base, candidate))
    return pairs, issues


def _metric_values(reports: list[dict[str, Any] | None], metric_id: str, field: str) -> list[float]:
    values: list[float] = []
    for report in reports:
        if report is None:
            continue
        summary = report["metrics"].get(metric_id)
        if _validate_summary(summary):
            values.append(float(summary[field]))
    return values


def _median_or_none(values: list[float]) -> float | None:
    return float(statistics.median(values)) if values else None


def _percentage_delta(base: float | None, candidate: float | None) -> float | None:
    if base is None or candidate is None or base == 0.0:
        return None
    return (candidate - base) / base * 100.0


def _pair_regressed(base_p95: float, candidate_p95: float, floor_ms: float) -> bool:
    delta = candidate_p95 - base_p95
    if delta < floor_ms:
        return False
    if base_p95 == 0.0:
        return candidate_p95 > 0.0
    return delta / base_p95 >= RELATIVE_THRESHOLD


def _metric_result(
    policy: MetricPolicy,
    base_reports: list[dict[str, Any] | None],
    candidate_reports: list[dict[str, Any] | None],
    pairs: list[tuple[int, dict[str, Any], dict[str, Any]]],
) -> dict[str, Any]:
    base_p50_values = _metric_values(base_reports, policy.metric_id, "p50_ms")
    base_p95_values = _metric_values(base_reports, policy.metric_id, "p95_ms")
    candidate_p50_values = _metric_values(candidate_reports, policy.metric_id, "p50_ms")
    candidate_p95_values = _metric_values(candidate_reports, policy.metric_id, "p95_ms")
    base_p50 = _median_or_none(base_p50_values)
    base_p95 = _median_or_none(base_p95_values)
    candidate_p50 = _median_or_none(candidate_p50_values)
    candidate_p95 = _median_or_none(candidate_p95_values)
    regressed_runs: list[int] = []
    compatible_runs: list[int] = []
    for run_number, base, candidate in pairs:
        base_summary = base["metrics"].get(policy.metric_id)
        candidate_summary = candidate["metrics"].get(policy.metric_id)
        if not _validate_summary(base_summary) or not _validate_summary(candidate_summary):
            continue
        compatible_runs.append(run_number)
        if policy.noise_floor_ms is not None and _pair_regressed(
            float(base_summary["p95_ms"]),
            float(candidate_summary["p95_ms"]),
            policy.noise_floor_ms,
        ):
            regressed_runs.append(run_number)
    comparison_available = len(compatible_runs) >= REQUIRED_REGRESSION_PAIRS
    relative_regression = comparison_available and len(regressed_runs) >= REQUIRED_REGRESSION_PAIRS
    candidate_available = len(candidate_p95_values) >= REQUIRED_REGRESSION_PAIRS
    telemetry_only = policy.noise_floor_ms is None and policy.budget_ms is None
    budget_miss = (
        candidate_available
        and policy.budget_ms is not None
        and candidate_p95 is not None
        and candidate_p95 > policy.budget_ms
    )
    if telemetry_only and candidate_available and comparison_available:
        status = "telemetry"
    elif relative_regression and budget_miss:
        status = "regression_and_budget_miss"
    elif relative_regression:
        status = "regression"
    elif budget_miss:
        status = "budget_miss"
    elif not candidate_available or not comparison_available:
        status = "telemetry_unavailable"
    else:
        status = "ok"
    delta = None if base_p95 is None or candidate_p95 is None else candidate_p95 - base_p95
    return {
        "benchmark_id": policy.benchmark_id,
        "metric_id": policy.metric_id,
        "label": policy.label,
        "budget_ms": policy.budget_ms,
        "noise_floor_ms": policy.noise_floor_ms,
        "telemetry_only": telemetry_only,
        "base": {
            "valid_runs": len(base_p95_values),
            "median_p50_ms": base_p50,
            "median_p95_ms": base_p95,
        },
        "candidate": {
            "valid_runs": len(candidate_p95_values),
            "median_p50_ms": candidate_p50,
            "median_p95_ms": candidate_p95,
        },
        "compatible_runs": compatible_runs,
        "regressed_runs": regressed_runs,
        "relative_threshold_percent": RELATIVE_THRESHOLD * 100.0,
        "relative_regression": relative_regression,
        "budget_miss": budget_miss,
        "delta_ms": delta,
        "delta_percent": _percentage_delta(base_p95, candidate_p95),
        "status": status,
    }


def _fmt_ms(value: float | None) -> str:
    return "unavailable" if value is None else f"{value:.3f} ms"


def _fmt_delta(value: float | None) -> str:
    return "unavailable" if value is None else f"{value:+.3f} ms"


def _fmt_percent(value: float | None) -> str:
    return "unavailable" if value is None else f"{value:+.1f}%"


def _fmt_budget(value: float | None) -> str:
    return "none" if value is None else f"{value:.3f} ms"


def _escape_message(value: str) -> str:
    return value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def _escape_property(value: str) -> str:
    return _escape_message(value).replace(":", "%3A").replace(",", "%2C")


def _emit_warning(title: str, message: str) -> None:
    print(f"::warning title={_escape_property(title)}::{_escape_message(message)}")


def _metric_warning(result: dict[str, Any]) -> None:
    status = result["status"]
    if status == "regression_and_budget_miss":
        title = f"Performance regression and budget miss: {result['label']}"
    elif status == "regression":
        title = f"Performance regression: {result['label']}"
    else:
        title = f"Performance budget exceeded: {result['label']}"
    details = (
        f"base p95 {_fmt_ms(result['base']['median_p95_ms'])}, "
        f"head p95 {_fmt_ms(result['candidate']['median_p95_ms'])}, "
        f"delta {_fmt_delta(result['delta_ms'])} ({_fmt_percent(result['delta_percent'])}), "
        f"budget {_fmt_budget(result['budget_ms'])}; "
        f"{len(result['regressed_runs'])}/{RUN_COUNT} paired runs exceeded the "
        f"15% and {_fmt_ms(result['noise_floor_ms'])} regression thresholds"
    )
    _emit_warning(title, details)


def _summary(metrics: list[dict[str, Any]], issues: list[str]) -> str:
    performance_warnings = [metric for metric in metrics if metric["relative_regression"] or metric["budget_miss"]]
    lines = [
        "# Performance advisory",
        "",
        "This check is advisory and non-blocking. Performance regressions never fail the workflow.",
        "",
        "Headless CPU timings are regression signals, not proof of 120 FPS on release hardware. GPU and rendered-frame costs require a fixed graphical runner.",
        "",
    ]
    if performance_warnings:
        lines.append(f"**Result:** {len(performance_warnings)} performance warning(s).")
    elif issues:
        lines.append("**Result:** No confirmed timing regression; some telemetry was unavailable.")
    else:
        lines.append("**Result:** No performance regressions or budget misses detected.")
    lines.extend(
        [
            "",
            "| Metric | Budget | Base p50 | Base p95 | Head p50 | Head p95 | Delta | Change | Regressed pairs | Status |",
            "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |",
        ]
    )
    for metric in metrics:
        lines.append(
            "| {label} | {budget} | {base_p50} | {base_p95} | {candidate_p50} | {candidate_p95} | {delta} | {percent} | {regressed}/{planned} | {status} |".format(
                label=metric["label"],
                budget=_fmt_budget(metric["budget_ms"]),
                base_p50=_fmt_ms(metric["base"]["median_p50_ms"]),
                base_p95=_fmt_ms(metric["base"]["median_p95_ms"]),
                candidate_p50=_fmt_ms(metric["candidate"]["median_p50_ms"]),
                candidate_p95=_fmt_ms(metric["candidate"]["median_p95_ms"]),
                delta=_fmt_delta(metric["delta_ms"]),
                percent=_fmt_percent(metric["delta_percent"]),
                regressed=len(metric["regressed_runs"]),
                planned=RUN_COUNT,
                status=metric["status"].replace("_", " "),
            )
        )
    if issues:
        lines.extend(["", "## Telemetry unavailable", ""])
        lines.extend(f"- {issue}" for issue in issues)
    lines.append("")
    return "\n".join(lines)


def _write_text(path: Path, content: str) -> str | None:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
    except (OSError, UnicodeError) as error:
        return f"could not write {path}: {error}"
    return None


def compare(base_dir: Path, candidate_dir: Path) -> tuple[dict[str, Any], str, list[str]]:
    reports: dict[str, dict[str, list[dict[str, Any] | None]]] = {}
    issues: list[str] = []
    pairs_by_benchmark: dict[str, list[tuple[int, dict[str, Any], dict[str, Any]]]] = {}
    for benchmark_id in REQUIRED_METRICS:
        base_reports, base_issues = _load_series(base_dir, benchmark_id, "base")
        candidate_reports, candidate_issues = _load_series(candidate_dir, benchmark_id, "head")
        pairs, pair_issues = _matching_pairs(base_reports, candidate_reports, benchmark_id)
        reports[benchmark_id] = {"base": base_reports, "candidate": candidate_reports}
        pairs_by_benchmark[benchmark_id] = pairs
        issues.extend(base_issues)
        issues.extend(candidate_issues)
        issues.extend(pair_issues)
    metrics = [
        _metric_result(
            policy,
            reports[policy.benchmark_id]["base"],
            reports[policy.benchmark_id]["candidate"],
            pairs_by_benchmark[policy.benchmark_id],
        )
        for policy in METRIC_POLICIES
    ]
    performance_warning_count = sum(
        1 for metric in metrics if metric["relative_regression"] or metric["budget_miss"]
    )
    result = {
        "schema_version": 1,
        "advisory": True,
        "run_count": RUN_COUNT,
        "relative_threshold_percent": RELATIVE_THRESHOLD * 100.0,
        "required_regression_pairs": REQUIRED_REGRESSION_PAIRS,
        "performance_warning_count": performance_warning_count,
        "telemetry_issue_count": len(issues),
        "metrics": metrics,
        "issues": issues,
    }
    return result, _summary(metrics, issues), issues


def run(arguments: list[str] | None = None) -> int:
    try:
        args = _parser().parse_args(arguments)
    except (ValueError, SystemExit) as error:
        _emit_warning("Performance telemetry unavailable", f"invalid comparator arguments: {error}")
        return 0
    output_json = Path(args.output_json)
    summary_path = Path(args.summary)
    try:
        result, summary, issues = compare(Path(args.base_dir), Path(args.candidate_dir))
    except Exception as error:
        issue = f"comparator could not process telemetry: {type(error).__name__}: {error}"
        result = {
            "schema_version": 1,
            "advisory": True,
            "performance_warning_count": 0,
            "telemetry_issue_count": 1,
            "metrics": [],
            "issues": [issue],
        }
        summary = _summary([], [issue])
        issues = [issue]
    for issue in issues:
        _emit_warning("Performance telemetry unavailable", issue)
    for metric in result["metrics"]:
        if metric["relative_regression"] or metric["budget_miss"]:
            _metric_warning(metric)
    json_error = _write_text(output_json, json.dumps(result, indent=2, sort_keys=True) + "\n")
    summary_error = _write_text(summary_path, summary)
    if json_error is not None:
        _emit_warning("Performance telemetry unavailable", json_error)
    if summary_error is not None:
        _emit_warning("Performance telemetry unavailable", summary_error)
    return 0


if __name__ == "__main__":
    raise SystemExit(run())
