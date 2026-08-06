# Actor animation extension

`BlockyHumanoidAnimator` owns one procedural clock for locomotion, body motion, air poses, landing, and rigid-limb actions. A `BlockyHumanoidAnimationProfile` is shareable across actors; runtime tuning duplicates the selected actor's profile before editing it.

Reusable humanoid scenes must preserve the named rig hierarchy used by `BlockyHumanoidAnimator` and provide `LeftFootMarker` and `RightFootMarker` at the authored ends of their rigid legs. Foot planting derives its reach from those markers, so humanoids can change limb proportions without changing animation code.

Each controller translates its own movement and perception into `ActorAnimationState`. `PlayerAnimationDriver` remains player-specific because mining, placement, inventory-selected melee actions, and per-action held-item poses have no mob consumer. The debug F10 panel owns the looping sword preview and exposes its action-specific held-item position and rotation alongside the shared profile and rigid-part transforms. The first mob should receive its own driver while reusing the humanoid animator and profile when its topology matches. Shared action behavior should be extracted only after a second real caller exists.

Quadrupeds, flying creatures, and other topologies need sibling animator implementations driven by the same state data; they should not imitate the humanoid hierarchy. Distant-update throttling belongs in the future mob scheduler through the existing explicit `advance_animation()` call, once real crowd visibility and distance data exist.
