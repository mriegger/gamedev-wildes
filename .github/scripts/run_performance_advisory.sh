#!/usr/bin/env bash
set -u

baseline_project_dir="${1:-baseline/src}"
candidate_project_dir="${2:-src}"
output_dir="${3:-/tmp/performance-advisory}"
repository_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
base_dir="$output_dir/base"
candidate_dir="$output_dir/candidate"
collection_issues="$output_dir/collection-issues.md"

cd "$repository_dir" || exit 0
mkdir -p "$base_dir/warmup" "$candidate_dir/warmup"
: > "$collection_issues"

emit_warning() {
  local title="$1"
  local message="$2"
  printf '::warning title=%s::%s\n' "$title" "$message"
  printf -- '- **%s:** %s\n' "$title" "$message" >> "$collection_issues"
}

run_benchmark() {
  local revision="$1"
  local project_dir="$2"
  local benchmark_id="$3"
  local script_name="$4"
  local pass_marker="$5"
  local run_name="$6"
  local result_dir="$7"
  local report_path="$result_dir/${benchmark_id}_${run_name}.json"
  local log_path="$result_dir/${benchmark_id}_${run_name}.log"
  local status

  timeout 900 godot --headless --path "$project_dir" --script "res://tests/$script_name" -- "--output=$report_path" > "$log_path" 2>&1
  status=$?
  cat "$log_path"
  if [ "$status" -ne 0 ]; then
    emit_warning "Performance telemetry unavailable" "$revision $benchmark_id run $run_name exited with status $status"
    if [ -f "$report_path" ]; then
      mv "$report_path" "$report_path.invalid"
    fi
    return
  fi
  if grep -Eq '^(ERROR:|SCRIPT ERROR:|WARNING:)' "$log_path"; then
    emit_warning "Performance telemetry unavailable" "$revision $benchmark_id run $run_name reported a Godot error or warning"
    if [ -f "$report_path" ]; then
      mv "$report_path" "$report_path.invalid"
    fi
    return
  fi
  if ! grep -Fq "$pass_marker" "$log_path"; then
    emit_warning "Performance telemetry unavailable" "$revision $benchmark_id run $run_name did not print $pass_marker"
    if [ -f "$report_path" ]; then
      mv "$report_path" "$report_path.invalid"
    fi
    return
  fi
  if [ ! -s "$report_path" ]; then
    emit_warning "Performance telemetry unavailable" "$revision $benchmark_id run $run_name did not produce a report"
  fi
}

run_revision() {
  local revision="$1"
  local project_dir="$2"
  local run_name="$3"
  local result_dir="$4"
  run_benchmark "$revision" "$project_dir" entity_efficiency entity_efficiency_benchmark.gd "ENTITY_EFFICIENCY PASS" "$run_name" "$result_dir"
  run_benchmark "$revision" "$project_dir" game_performance game_performance_benchmark.gd "GAME_PERFORMANCE PASS" "$run_name" "$result_dir"
}

revision_available() {
  local revision="$1"
  local project_dir="$2"
  if [ ! -f "$project_dir/project.godot" ]; then
    emit_warning "Performance telemetry unavailable" "$revision project was not available at $project_dir"
    return 1
  fi
  return 0
}

baseline_available=0
candidate_available=0
if revision_available baseline "$baseline_project_dir"; then
  baseline_available=1
fi
if revision_available candidate "$candidate_project_dir"; then
  candidate_available=1
fi
if ! command -v godot >/dev/null 2>&1; then
  emit_warning "Performance telemetry unavailable" "Godot was not available on the runner"
  baseline_available=0
  candidate_available=0
fi

if [ "$baseline_available" -eq 1 ]; then
  run_revision baseline "$baseline_project_dir" warmup "$base_dir/warmup"
fi
if [ "$candidate_available" -eq 1 ]; then
  run_revision candidate "$candidate_project_dir" warmup "$candidate_dir/warmup"
fi

for pair in 1 2 3 4 5; do
  if [ $((pair % 2)) -eq 1 ]; then
    if [ "$baseline_available" -eq 1 ]; then
      run_revision baseline "$baseline_project_dir" "$pair" "$base_dir"
    fi
    if [ "$candidate_available" -eq 1 ]; then
      run_revision candidate "$candidate_project_dir" "$pair" "$candidate_dir"
    fi
  else
    if [ "$candidate_available" -eq 1 ]; then
      run_revision candidate "$candidate_project_dir" "$pair" "$candidate_dir"
    fi
    if [ "$baseline_available" -eq 1 ]; then
      run_revision baseline "$baseline_project_dir" "$pair" "$base_dir"
    fi
  fi
done

exit 0
