#!/usr/bin/env bash
set -euo pipefail

timeout_seconds="${1:?timeout seconds required}"
pass_marker="${2:?pass marker required}"
log_path="${3:?log path required}"
shift 3
if [ "$#" -lt 2 ] || [ "$1" != "--" ]; then
  printf '%s\n' "usage: run_godot_check.sh <timeout> <pass-marker> <log-path> -- <command> [args...]" >&2
  exit 2
fi
shift

set +e
timeout "$timeout_seconds" "$@" 2>&1 | tee "$log_path"
pipeline_status=("${PIPESTATUS[@]}")
set -e

if [ "${pipeline_status[0]}" -ne 0 ] || [ "${pipeline_status[1]}" -ne 0 ]; then
  printf '%s\n' "Godot check exited ${pipeline_status[0]} and tee exited ${pipeline_status[1]}"
  exit 1
fi
if grep -Eq '^(ERROR:|SCRIPT ERROR:|\[[^]]+\] (ERROR|WARNING))' "$log_path"; then
  printf '%s\n' "Godot check reported an error or scoped warning"
  exit 1
fi
if grep -q "FAIL:" "$log_path"; then
  printf '%s\n' "Godot check reported a failure"
  exit 1
fi
if ! grep -Fq "$pass_marker" "$log_path"; then
  printf '%s\n' "Godot check did not print: $pass_marker"
  exit 1
fi
