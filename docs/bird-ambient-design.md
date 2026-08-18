# Ambient Bird Design

## Status

Implementation proposal for a first-pass ambient bird species. The design is scoped to procedural visuals and deterministic movement; it does not require an external model or audio asset.

## Player Experience

Birds make the daytime world feel inhabited without becoming a new progression system. A bird appears in flight, chooses a clear landing site, descends, idles and walks briefly, then takes off and repeats the cycle elsewhere. Birds fade away when night begins and return through normal ambient spawning the next day.

The first version is successful when:

- Birds spawn only during the existing daytime window, 06:00 through 18:59.
- Active birds begin fading out at 19:00 and no birds remain active at night.
- At most four birds are active at once.
- Birds cannot be acquired as melee targets, damaged, killed, or rewarded with XP.
- Birds visibly alternate between flight, landing, grounded idle, walking, and takeoff.
- Birds never spawn inside terrain and land only on grass, dirt, or sand with enough body clearance.
- Grounded birds use the shared bounded navigation budget; flying birds do not run voxel path searches.
- The same world seed and behavior seed produce the same spawn and behavior sequence.
- Birds remain transient runtime entities and are not written to saves.

## Non-Goals

- Combat interaction, damage, death, XP, loot, food, taming, nests, eggs, or breeding
- Perching on trees, structures, water, or farmland
- Bird attacks or flock coordination
- Bird vocalizations or changes to the existing dawn-chorus ambience
- A GLB model, texture, or new block type
- Three-dimensional pathfinding

## Existing Architecture

The entity system already provides the required ownership boundaries:

- `EntityDefinition` is the catalog-owned content definition.
- `WorldEntityCoordinator` owns ambient population scheduling and seeded spawn sampling.
- `EntityRuntime` owns active actors, validation, pooling, stats, spatial indexing, and retirement.
- `EntityActor` owns one entity's runtime movement and presentation coordination.
- Species brains are deterministic `RefCounted` domain objects.
- `Game` and `game.tscn` compose the system through explicit `setup()` calls.

Birds should use those boundaries. No bird-specific branch belongs in `Game`, and no global registry or event bus is needed.

## Feature Layout

```text
src/entities/bird/
  bird_actor.gd
  bird_animation_driver.gd
  bird_behavior.tres
  bird_behavior_definition.gd
  bird_brain.gd
  bird_stats.tres
  bird.tscn
  bird_visual.tscn
  tests/
    bird_behavior.gd
    bird_runtime_integration.gd
src/entities/definitions/bird.tres
```

## Generic Spawn Placement

Birds are the first entity that must be valid without ground directly beneath its feet. Represent that rule in `EntityDefinition` rather than checking the bird ID.

```gdscript
enum SpawnPlacement {
	GROUNDED,
	AERIAL,
}

@export var spawn_placement: SpawnPlacement = SpawnPlacement.GROUNDED
@export_range(1, 32, 1) var ambient_aerial_altitude_min_blocks: int = 8
@export_range(1, 32, 1) var ambient_aerial_altitude_max_blocks: int = 14
@export var ambient_despawn_outside_spawn_phase: bool = false
@export var combat_targetable: bool = true
```

`EntityDefinition.validate()` must reject an aerial definition whose minimum altitude exceeds its maximum and a non-targetable definition with a nonzero experience reward. Existing zombie and sheep resources retain the default `GROUNDED`, persistent-phase, and targetable values.

`EntitySpawnGeometry.can_spawn()` remains the authoritative runtime entry point and dispatches by `spawn_placement`:

- `can_spawn_grounded()` preserves the current collision and ground-support checks.
- `can_spawn_aerial()` requires aligned finite spawn coordinates, an unobstructed body volume, and no immediate ground support. It does not enforce ambient floor IDs because explicit level spawns are not ambient spawns.
- `get_bounds()` remains unchanged.

`WorldEntityCoordinator` continues to enforce ambient-only rules. It checks the surface block against `ambient_spawn_floor_ids`, builds either a grounded or aerial candidate, then calls `EntitySpawnGeometry.can_spawn()` before submitting the request. `EntityRuntime.try_spawn_batch()` validates the request again immediately before committing it. The coordinator's private clearance check can be removed so collision rules are not duplicated.

For an aerial candidate, the coordinator chooses an integer altitude in the configured inclusive range and places the bird that many blocks above the walkable surface. The existing 18–36 block horizontal spawn annulus and streaming-readiness check still apply.

Before advancing active actors, `WorldEntityCoordinator` retires any definition with `ambient_despawn_outside_spawn_phase` when its configured phase is inactive. This is a generic definition rule rather than a bird-ID check. Bird retirement uses the existing despawn fade and does not trigger combat death presentation.

`MeleeCombatCoordinator` excludes definitions with `combat_targetable == false` while acquiring targets and validates the flag again when committing locked contacts. `EntityRuntime.try_apply_damage()` also rejects non-targetable definitions, keeping the rule authoritative even for direct callers.

## Population Capacity

The current caps are six sheep, six zombies, and twelve total entities. Birds disappear at night, but sheep and zombies retain their existing cross-phase persistence. Without more capacity, a populated world could still leave no room for the next day's birds.

Increase `WorldEntityCoordinator.MAX_TOTAL_ACTIVE` from 12 to 16. This preserves existing sheep and zombie behavior and allows all three caps to coexist during the day: six sheep, six zombies, and four birds. At night, the four birds fade out and the active population is bounded to twelve. Keep `MAX_RETIRING_VISUALS` at 12; retirement remains independently bounded. Update population and efficiency tests to exercise the new 16-actor bound.

The coordinator still creates at most one actor per two-second spawn interval. With the current catalog-order scheduler, a fresh daytime world fills the six-sheep cap before spawning birds, so the first bird is expected after approximately 12 seconds and the four-bird cap after approximately 20 seconds.

## Bird Content Definition

`src/entities/definitions/bird.tres` uses:

| Field | Value |
| --- | --- |
| `id` | `&"bird"` |
| `ambient_spawn_phase` | `DAY` |
| `ambient_max_active` | `4` |
| `ambient_spawn_floor_ids` | grass, dirt, sand |
| `spawn_placement` | `AERIAL` |
| `ambient_despawn_outside_spawn_phase` | `true` |
| `combat_targetable` | `false` |
| Ambient altitude | 8–14 blocks |
| Body width / height | 0.4 / 0.5 |
| Maximum HP | 1, unused while untargetable |
| Defense / strength | 0 / 0 |
| Experience reward | 0 |

Append the definition to `entity_catalog.tres`. No `game.tscn` change is required.

## Behavior Definition

`BirdBehaviorDefinition` extends `EntityBehaviorDefinition` and owns all tuning values used by the bird actor and brain:

| Property | Initial value |
| --- | ---: |
| `flight_speed` | 5.0 |
| `flight_acceleration` | 12.0 |
| `landing_speed` | 3.0 |
| `takeoff_speed` | 6.5 |
| `grounded_walk_speed` | 1.0 |
| `gravity` | 25.0 |
| `jump_velocity` | 5.0 |
| `repath_seconds` | 0.5 |
| `grounded_wander_radius` | 4.0 |
| `landing_search_radius` | 28.0 |
| `cruise_altitude_min_blocks` | 9 |
| `cruise_altitude_max_blocks` | 14 |
| `landing_approach_distance` | 3.0 |
| `landed_idle_min_seconds` | 1.5 |
| `landed_idle_max_seconds` | 3.0 |
| `grounded_walk_seconds` | 2.5 |
| `walks_before_takeoff` | 2 |
| `landing_retry_seconds` | 1.0 |

Validation rejects non-finite or non-positive movement values, inverted ranges, a flight speed below the grounded speed, and a walk count below one.

## Deterministic State Machine

`BirdBrain` is a `RefCounted` object with a seeded `RandomNumberGenerator`. It owns behavior state, timers, walk count, and random samples. It does not query nodes or mutate the voxel world.

```text
CRUISE -> DESCEND -> GROUNDED_IDLE -> GROUNDED_WALK
   ^                                      |
   |                                      |
   +--------------- TAKEOFF <-------------+
```

- `CRUISE`: move at cruise altitude toward the approach point above the selected landing site.
- `DESCEND`: move toward the landing site's feet position. Ground contact enters `GROUNDED_IDLE`.
- `GROUNDED_IDLE`: wait for a seeded duration, then request a grounded walk goal.
- `GROUNDED_WALK`: walk for the configured duration. After two walks, enter `TAKEOFF`; otherwise return to idle.
- `TAKEOFF`: climb to cruise altitude, then select another landing site and enter `CRUISE`.

The brain exposes state and narrow transition inputs such as elapsed time, ground contact, goal reached, and movement rejection. The actor owns the current world-space targets because those depend on voxel queries. Nighttime retirement bypasses the brain and remains owned by `WorldEntityCoordinator` and `EntityRuntime`.

## Landing Selection and Movement

`BirdActor` extends `EntityActor`, accepts only `BirdBehaviorDefinition`, and owns one `VoxelPathFollower` for its grounded state.

Landing selection is bounded to eight samples per selection event:

1. Ask the brain for a seeded offset within `landing_search_radius`.
2. Find the highest solid surface at that column through the injected `VoxelSpace`.
3. Reject any supporting block outside the definition's `ambient_spawn_floor_ids`.
4. Validate the feet position with `EntitySpawnGeometry.can_spawn_grounded()`.
5. Store the first valid landing site and its approach point.

If all samples fail, remain airborne and retry after `landing_retry_seconds`. Do not repeat the search every frame.

In flight, compute the desired three-dimensional velocity and approach it with `velocity.move_toward(desired_velocity, flight_acceleration * delta)`. Apply it with `VoxelBodySolver.sweep()`. A blocked sweep invalidates the approach, climbs the bird away from the obstruction, and schedules a bounded retarget. This provides voxel collision without introducing a 3D pathfinder.

On the ground, use `VoxelPathFollower.advance()`, `apply_path_follow_result()`, `limit_planar_velocity()`, and `advance_voxel_motion()` in the same ownership pattern as `SheepActor`. A rejected path returns the brain to idle and does not consume additional searches in that frame.

The runtime's existing separation velocity applies in all states. The bird actor limits the combined velocity according to its current grounded or flying speed.

## Presentation

`bird_visual.tscn` is built from `BoxMesh` primitives and faces positive Z, matching the existing actor yaw convention:

```text
RigRoot
  BodyPivot
    Body
    HeadAnchor/HeadPivot
      Head
      Beak
    LeftWingPivot/LeftWing
    RightWingPivot/RightWing
    TailPivot/Tail
    LeftLegPivot/LeftLeg/LeftFoot
    RightLegPivot/RightLeg/RightFoot
```

Initial proportions:

- Body: 0.40 × 0.25 × 0.50, warm brown
- Head: 0.22 cube, warm brown
- Beak: 0.12 × 0.08 × 0.12, muted yellow
- Wings: 0.35 × 0.05 × 0.25, darker brown
- Tail: 0.18 × 0.06 × 0.18, darker brown
- Legs and feet: narrow, muted orange-brown

`BirdAnimationDriver` extends `EntityAnimationDriver` and derives presentation from actor state:

- Cruise and takeoff: fast wing flap and subtle body pitch
- Descent: slower, wider wing pose with legs lowered
- Idle: folded wings, breathing, head turns, and occasional tail movement
- Walk: folded wings, short alternating steps, and body bob

The bird has no hit or death animation in the first pass because combat cannot target it. Nightfall and distance retirement use the shared visual fade.

## Silent Entity Presentation

`EntityActor` currently requires a valid `EntityVocalizations` node and profile, so the draft concept of a silent placeholder would fail setup. Make vocalizations an optional presentation dependency:

- An empty `vocalizations_path` means the species has no vocalization presenter.
- `EntityActor.setup()`, `begin_despawn_fade()`, and `begin_death_retirement()` call it only when present.
- `has_valid_presentation()` validates the vocalization node only when a path is configured.
- Existing sheep and zombie scenes remain configured and unchanged.
- `bird.tscn` omits the vocalization node and path.

This is a real second presentation mode required by the bird and avoids a fake silent audio asset. The existing daytime bird ambience remains the only bird audio and its scheduling is unchanged: it fades in from 06:00–08:00, stays full through 17:00, fades out through 19:00, and is silent at night.

## Tests

### Focused bird tests

- Identical seeds and inputs produce identical state, timers, offsets, and transitions.
- Different seeds produce at least one different sampled goal.
- The idle/walk count leads to takeoff after exactly two completed walks.
- A blocked landing candidate is rejected and search attempts remain capped at eight.
- Flight collision retargets without entering solid voxels.
- A bird can land, walk through the shared navigation budget, and take off again.
- Nightfall retires every bird through the ordinary fade and prevents replacement spawns.
- Melee target acquisition and direct damage both reject birds.
- Bird teardown returns the orphan-node count to its baseline.

### Existing test updates

- `entity_domain.gd`: assert the bird catalog entry, behavior compatibility, spawn placement, zero reward, daytime eligibility, nighttime retirement, and combat exclusion.
- `entity_placement_integration.gd`: cover grounded and aerial geometry validation, including blocked body volumes and immediate support rejection.
- `entity_population_integration.gd`: verify aerial spawn altitude, annulus, streaming readiness, four-bird cap, and spatial-index bounds.
- `entity_species_population_integration.gd`: replace the two-species assumption with six sheep, six zombies, four daytime birds, zero nighttime birds, and a total cap of 16.
- `entity_combat_integration.gd`: verify that birds are absent from acquired targets and cannot be damaged through a forged locked-target command.
- `entity_efficiency_benchmark.gd`: arrange and tick the full 16-actor population while retaining the one-search-per-frame navigation bound.
- `soak_entity_streaming.gd`: include bird spawn, movement, despawn, suspension, and teardown.
- CI: register both focused bird test scripts and keep all existing entity checks enabled.

## Implementation Order

1. Add generic spawn placement to `EntityDefinition` and centralize placement checks in `EntitySpawnGeometry`.
2. Update `WorldEntityCoordinator` to sample aerial positions and raise the bounded active cap to 16.
3. Add generic phase retirement and combat targetability rules, then make entity vocalizations optional.
4. Add and validate `BirdBehaviorDefinition` and `BirdBrain` with focused deterministic tests.
5. Add `BirdActor`, bounded landing selection, flight collision, and grounded navigation.
6. Add the procedural visual, animation driver, stats, scene, definition, and catalog entry.
7. Update population, placement, efficiency, streaming, and domain coverage.
8. Run the complete entity and world-streaming CI suite and perform a daytime visual tuning pass.

## Risks and Mitigations

| Risk | Mitigation |
| --- | --- |
| Flight intersects cliffs or trees | Swept voxel movement, obstruction climb, and bounded retargeting |
| Landing search spikes | Eight attempts only on selection, followed by a one-second retry delay |
| Birds consume grounded path budget while flying | Construct the follower once but call it only in `GROUNDED_WALK` |
| New species prevents future daytime birds from spawning | Raise the total cap to the explicit 6 + 6 + 4 population bound |
| Birds remain visible after dusk | Retire phase-bound definitions at 19:00 through the existing fade path |
| A forged target list damages an ambient bird | Validate `combat_targetable` during acquisition, commit, and runtime damage |
| Catalog-order spawn delay is mistaken for failure | Document and test the expected first-bird window of about 12 seconds |
| Empty audio placeholder fails actor validation | Support an explicitly absent vocalization presenter |
| State and presentation diverge | Brain owns behavior state; actor queries it; animation only presents actor state |
