#!/usr/bin/env bash
# Build a macOS .app for a game, dispatching on engine.
#
# Usage:  build_macos.sh <engine> <name> [project_dir]
#   engine       godot | love | raylib
#   name         game name (used for the .app / bundle id)
#   project_dir  source root (default: src)
#
# Produces  <cwd>/build/<safe_name>.app  and writes app_path=<abs> to
# $GITHUB_OUTPUT (falls back to stdout when run locally).
#
# Version pins via env: GODOT_VERSION (4.3), LOVE_VERSION (11.5),
# RAYLIB_VERSION (5.0 -- must match the game Makefile's raylib path).
set -euo pipefail

engine="${1:?engine required}"
name="${2:?name required}"
project_dir="${3:-src}"

GODOT_VERSION="${GODOT_VERSION:-4.3}"
LOVE_VERSION="${LOVE_VERSION:-11.5}"
RAYLIB_VERSION="${RAYLIB_VERSION:-5.0}"

root="$PWD"
build_dir="$root/build"
safe_name="$(printf '%s' "$name" | tr ' /:' '___')"
app="$build_dir/${safe_name}.app"
bundle_id="com.metagamedev.$(printf '%s' "$safe_name" | tr '[:upper:]' '[:lower:]')"
mkdir -p "$build_dir"

log() { echo "==> $*"; }

# --- engine recipes --------------------------------------------------------

build_godot() {
  local ver="$GODOT_VERSION"
  local base="https://github.com/godotengine/godot/releases/download/${ver}-stable"
  log "Installing Godot ${ver} + export templates"
  curl -fsSL -o /tmp/godot.zip "${base}/Godot_v${ver}-stable_macos.universal.zip"
  rm -rf /tmp/godot && unzip -q -o /tmp/godot.zip -d /tmp/godot
  local godot_bin="/tmp/godot/Godot.app/Contents/MacOS/Godot"
  chmod +x "$godot_bin"

  curl -fsSL -o /tmp/templates.tpz "${base}/Godot_v${ver}-stable_export_templates.tpz"
  rm -rf /tmp/godot-templates && unzip -q -o /tmp/templates.tpz -d /tmp/godot-templates
  local tdir="$HOME/Library/Application Support/Godot/export_templates/${ver}.stable"
  mkdir -p "$tdir"
  cp -f /tmp/godot-templates/templates/* "$tdir"/

  [ -f "$project_dir/project.godot" ] \
    || { echo "::error::no project.godot in ${project_dir}"; exit 1; }
  [ -f "$project_dir/export_presets.cfg" ] \
    || { echo "::error::no export_presets.cfg in ${project_dir} (add a preset named 'macOS')"; exit 1; }

  log "Importing project assets"
  "$godot_bin" --headless --path "$project_dir" --import 2>/dev/null || true
  log "Exporting macOS app"
  "$godot_bin" --headless --path "$project_dir" --export-release "macOS" "$app"
  [ -d "$app" ] || { echo "::error::Godot export produced no .app at ${app}"; exit 1; }
}

build_love() {
  local ver="$LOVE_VERSION"
  [ -f "$project_dir/main.lua" ] \
    || { echo "::error::no main.lua in ${project_dir}"; exit 1; }
  log "Installing LOVE ${ver}"
  curl -fsSL -o /tmp/love.zip \
    "https://github.com/love2d/love/releases/download/${ver}/love-${ver}-macos.zip"
  rm -rf /tmp/love && unzip -q -o /tmp/love.zip -d /tmp/love

  log "Packaging .love"
  local love_file="$build_dir/game.love"
  rm -f "$love_file"
  ( cd "$project_dir" && zip -9 -r -q "$love_file" . -x '*.git*' -x 'export_presets.cfg' )

  log "Fusing into .app"
  rm -rf "$app"
  cp -R "/tmp/love/love.app" "$app"
  cp "$love_file" "$app/Contents/Resources/"
  local plist="$app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleName ${safe_name}" "$plist" || true
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${bundle_id}" "$plist" || true
  # so the .app launches the game rather than registering as a .love handler
  /usr/libexec/PlistBuddy -c "Delete :CFBundleDocumentTypes" "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Delete :UTExportedTypeDeclarations" "$plist" 2>/dev/null || true
}

build_raylib() {
  local ver="$RAYLIB_VERSION"
  [ -f "$project_dir/Makefile" ] \
    || { echo "::error::no Makefile in ${project_dir}"; exit 1; }
  log "Building raylib ${ver} static lib"
  curl -fsSL -o /tmp/raylib.tar.gz \
    "https://github.com/raysan5/raylib/archive/refs/tags/${ver}.tar.gz"
  tar -xzf /tmp/raylib.tar.gz -C /tmp   # -> /tmp/raylib-<ver>
  make -C "/tmp/raylib-${ver}/src" PLATFORM=PLATFORM_DESKTOP -j3

  log "Building game via Makefile"
  make -C "$project_dir"

  # Resolve the built binary from the Makefile's OUT (relative to project_dir).
  local out_rel
  out_rel="$(make -C "$project_dir" -p 2>/dev/null \
    | sed -n 's/^OUT *= *//p' | head -n1 | tr -d '[:space:]')"
  local bin
  if [ -n "$out_rel" ]; then
    bin="$(cd "$project_dir" && cd "$(dirname "$out_rel")" && echo "$PWD/$(basename "$out_rel")")"
  else
    bin="$root/${safe_name}"
  fi
  [ -f "$bin" ] || { echo "::error::built binary not found (looked for '${bin}')"; exit 1; }

  log "Wrapping binary in .app"
  rm -rf "$app"
  mkdir -p "$app/Contents/MacOS"
  cp "$bin" "$app/Contents/MacOS/${safe_name}"
  chmod +x "$app/Contents/MacOS/${safe_name}"
  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${safe_name}</string>
  <key>CFBundleExecutable</key><string>${safe_name}</string>
  <key>CFBundleIdentifier</key><string>${bundle_id}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
}

# --- dispatch --------------------------------------------------------------

case "$engine" in
  godot)  build_godot ;;
  love)   build_love ;;
  raylib) build_raylib ;;
  *)      echo "::error::unsupported engine: '${engine}'"; exit 1 ;;
esac

log "Built ${app}"
echo "app_path=${app}" >> "${GITHUB_OUTPUT:-/dev/stdout}"
