#!/usr/bin/env bash
# Print the task.toml paths that a run should build, one per line.
#
# - workflow_dispatch: resolves tasks/<TASK_INPUT>/task.toml
# - push: task.toml files changed between BEFORE and SHA
# - fallback (first push / unknown BEFORE): every tracked task.toml
#
# Env: GH_EVENT (or GITHUB_EVENT_NAME), TASK_INPUT, BEFORE, SHA.
set -euo pipefail

event="${GH_EVENT:-${GITHUB_EVENT_NAME:-}}"
only_tasks='^tasks/[^/]+/task\.toml$'

list_all() {
  git ls-files -- tasks | grep -E "$only_tasks" || true
}

if [ "$event" = "workflow_dispatch" ]; then
  task="${TASK_INPUT:-}"
  [ -n "$task" ] || { echo "workflow_dispatch requires a 'task' input" >&2; exit 1; }
  path="tasks/${task}/task.toml"
  [ -f "$path" ] || { echo "no such task.toml: $path" >&2; exit 1; }
  echo "$path"
  exit 0
fi

before="${BEFORE:-}"
sha="${SHA:-HEAD}"

# No usable base commit (first push, force-push, or missing) -> build all.
if [ -z "$before" ] || printf '%s' "$before" | grep -qE '^0+$' \
   || ! git cat-file -e "${before}^{commit}" 2>/dev/null; then
  list_all
  exit 0
fi

git diff --name-only "$before" "$sha" -- tasks | grep -E "$only_tasks" || true
