# Project Wildes - agent working rules

This is a directory for a isometric voxel game called Project Wildes. 

Godot 4.7 / GDScript, Systems are built in `game.tscn` and wired via `setup()` calls. No autoloads, no singletons. Keep it that way. 

## Renames and refactors
1. No external API consumers. When you rename something, rename every call site and delete the old name. Never leave behind an alias const, a forwarding one liner, a reexport, a thin subclass, or a duplicate signal. 
2. Never keep an old API shape alongside a new one for "compatibility". No int/enum facade over string keyed table, no `old_foo()` calling `foo_new()`. Migrate callers and delete the old path in the same change. 

## Dead code
1. Do not add a function, constant, signal, variable, or parameter that has no caller. If it is for a feature that hasnt landed, leave it out.
2. Do not emit a signal nothing connects to. Wire the consumer in the same change or dont declare the signal. 
3. D not add optional parameters that no call site passes.
4. Do not write defensive branches for conditions that cannot occur (`has_method()` on a method the same base class always has, a fallback behind an early `return`, `if x: A else: A`).
5. Before reporting done, grep every symbol you added. Zero callers means delete it.

## Do not write code that undoes itself
1. Don't call a helper and then overwrite every field to set.
2. Do not build a paramterized API and then hardcode the values at the callsite. 
3. If two functions encode the same rule (`can_x()` predicate and the `x()` that mutates), one MUST call the other. Never maintain them in parallel. 

## Comments
1. Do not add comments

## Shared code
1. Extract a shared base class rather then copying a block into a second file. Two near identical copies always drift.

## Verification - REQUIRED, DO NOT SKIP.
1. Boot: `/Applications/Godot.app/Contents/MacOS/Godot --path src --headless --quit`
2. Behavior: Write a temporary `extends SceneTree` script under `src/`, run it with `--path src --headless --script res://tmp_x.gd`, then DELETE it. Instantiate `res://ui/hud/hud.tscn`, add it to `root`, call `setup_with_camera(inv, null)`, let around 120 frames pass, then inspect real node state. Drive real input with `root.push_input(event, true)`.
3. Leave the working tree exactly as you found it. `git status` must show no temp files.

## Tests — run periodically to prevent regressions
1. After any inventory, worldgen, HUD/drag, streaming, player animation, animation tuning, or tool change — and before reporting DONE — run the headless suite locally. CI runs the suite in parallel; `.github/workflows/tests.yml` defines the jobs and `src/tests/README.md` documents their invariants.
2. Inventory fuzz (RefCounted, ~100k seq/s): `/Applications/Godot.app/Contents/MacOS/Godot --path src --headless --script res://tests/inventory_fuzz_runner.gd -- --seqs=20000 --ops=20` — expect `ALL PASS`. Smoke: `--seqs=5000 --ops=20`.
3. World golden hash (seed 1337, `x[-32,32) z[-32,32) y[0,128)`): `/Applications/Godot.app/Contents/MacOS/Godot --path src --headless --script res://tests/world_golden_hash.gd` — expect `GOLDEN PASS`. If you intentionally reshaped terrain (noise/spline/biome/lake/river), rerun with `-- --update` and commit the new `src/tests/golden_world_hash.json`.
4. HUD headless integration: `/Applications/Godot.app/Contents/MacOS/Godot --path src --headless --script res://tests/hud_integration.gd` — expect `HUD_INTEGRATION PASS orphan=0 previews=0` (mid-drag 1 preview, 0 after release).
5. Player animation integration: `/Applications/Godot.app/Contents/MacOS/Godot --path src --headless --script res://tests/player_animation_integration.gd` — expect `PLAYER_ANIMATION PASS orphan=0`.
6. Animation tuning integration: `/Applications/Godot.app/Contents/MacOS/Godot --path src --headless --script res://tests/animation_tuning_panel_integration.gd` — expect `ANIMATION_TUNING PASS orphan=0`.
7. Tool system integration: `/Applications/Godot.app/Contents/MacOS/Godot --path src --headless --script res://tests/tool_system_integration.gd` — expect `TOOL_SYSTEM PASS orphan=0`.
8. World streaming soak (real `game.tscn`, 900 frames): `/Applications/Godot.app/Contents/MacOS/Godot --path src --headless --script res://tests/soak_world_streaming.gd` — expect `SOAK PASS` with bounded chunks and no orphans.
9. Do not land with any red test job. Details and invariants live in `src/tests/README.md`.

## Definition of "DONE"
1. Every new symbol has a caller.
2. No old name survives a rename
3. Headless boot is clean
4. The behavior is verified by running it, not by reading it. 
5. `git status` shows only intended files.
