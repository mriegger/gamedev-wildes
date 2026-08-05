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
2. Behavior: Write a temporary `extends SceneTree` script under `src/`, run it with `--path src --headless --script res://tmp_x.gd`, then DELETE it. Instantiate `res://ui/hud.tscn`, add it to `root`, call `setup_with_camera(inv, null)`, let around 120 frames pass, then inspect real node state. Drive real input with `root.push_input(event, true)`.
3. Leave the working tree exactly as you found it. `git status` must show no temp files. 

## Definition of "DONE"
1. Every new symbol has a caller.
2. No old name survives a rename
3. Headless boot is clean
4. The behavior is verified by running it, not by reading it. 
5. `git status` shows only intended files.