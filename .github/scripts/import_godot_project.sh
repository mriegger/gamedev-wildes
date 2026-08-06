#!/usr/bin/env bash
set -euo pipefail

godot_bin="${1:?godot executable required}"
project_dir="${2:?project directory required}"
initial_log="${3:?initial import log required}"
validation_log="${4:?validation import log required}"

if ! "$godot_bin" --headless --path "$project_dir" --import >"$initial_log" 2>&1; then
  cat "$initial_log"
  exit 1
fi
allowed_initial_error_pattern="^("
allowed_initial_error_pattern+="ERROR: Cannot open file 'res://\\.godot/imported/RobotoSlab-Regular\\.ttf-[0-9a-f]+\\.fontdata'\\.|"
allowed_initial_error_pattern+="ERROR: Failed loading resource: res://\\.godot/imported/RobotoSlab-Regular\\.ttf-[0-9a-f]+\\.fontdata\\.|"
allowed_initial_error_pattern+="ERROR: Failed loading resource: res://assets/fonts/RobotoSlab-Regular\\.ttf\\.|"
allowed_initial_error_pattern+="ERROR: res://ui/theme/wildes_theme\\.tres:6 - Parse Error: \\[ext_resource\\] referenced non-existent resource at: res://assets/fonts/RobotoSlab-Regular\\.ttf\\.|"
allowed_initial_error_pattern+="ERROR: Failed loading resource: res://ui/theme/wildes_theme\\.tres\\.|"
allowed_initial_error_pattern+="ERROR: Error loading custom project theme 'res://ui/theme/wildes_theme\\.tres'"
allowed_initial_error_pattern+=")$"
unexpected_initial_error=0
while IFS= read -r line; do
  if [[ "$line" =~ ^(ERROR:|SCRIPT\ ERROR:) ]] && [[ ! "$line" =~ $allowed_initial_error_pattern ]]; then
    printf '%s\n' "$line"
    unexpected_initial_error=1
  fi
done < "$initial_log"
if [ "$unexpected_initial_error" -ne 0 ]; then
  exit 1
fi
tail -n 100 "$initial_log"

if ! "$godot_bin" --headless --path "$project_dir" --import >"$validation_log" 2>&1; then
  cat "$validation_log"
  exit 1
fi
if grep -Eq '^(ERROR:|SCRIPT ERROR:)' "$validation_log"; then
  cat "$validation_log"
  exit 1
fi
tail -n 100 "$validation_log"
test -d "$project_dir/.godot"
