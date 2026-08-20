# Dungeon chest authoring and rewards

Dungeon chests are generated content, not persistent overworld containers. A Level Module supplies
the physical chest marker, its `LevelRoomRequirement` supplies the repeat loot pools, and its
`LevelDefinition` may supply one dungeon-wide guaranteed reward. The same room geometry can
therefore serve a progression dungeon, a farmable dungeon, or a future generated dungeon without
embedding reward rules in the module.

## Runtime rules

Every generated room whose module has a chest marker contains one physical chest. Chest rooms are
passive rooms: they do not create a local enemy wave or a branch seal. They are not safe rooms;
enemies from another room use the same dungeon navigation and may enter and attack the player.
Dungeon chests are take-only and disappear with the attempt runtime, so players cannot use them as
persistent storage.

When a level has an unclaimed `LevelOneTimeChestRewardDefinition`:

- one generated chest is selected deterministically from all chest placements;
- that chest contains only the guaranteed bundle for the attempt;
- every other chest uses its room requirement's base repeat pool; and
- the guaranteed chest and contents remain deterministic until the reward is claimed.

Clicking any item in the guaranteed chest or pressing `Claim Reward` transfers the complete bundle
directly into the player's inventory and records the claim in the same validated transaction. The
game immediately requests a save after a successful claim. The claim is separate from completion:
death, quit, or another abandoned attempt keeps both the inventory items and the claimed reward ID,
but does not increment the dungeon completion count.

The guaranteed bundle is all-or-nothing. If every item will not fit, the chest and inventory remain
unchanged and the game displays `Inventory full — drop items first`. Partial dragging from that
chest is disabled. Repeat loot keeps the normal direct-transfer behavior, including partial moves
when appropriate.

A run that began with an unclaimed guaranteed reward completes when the player claims that reward
and exits alive. A run that began with the reward already claimed, or belongs to a dungeon without
a guaranteed reward, completes after any positive repeat chest-to-inventory transfer and an alive
exit. A qualifying exit increments completion once; repeated exit requests cannot reuse the same
transfer. Enemy clearance is not a completion condition today. If that rule is added later, the
encounter state owner must provide it as another validated completion input.

The repeat loot tier is selected once when an attempt starts. Before the first completion, every
repeat chest uses `chest_loot_pool`. Beginning with the attempt after `completion_count` reaches one,
the chest uses `post_first_completion_chest_loot_pool` when one is configured, otherwise it keeps
using the base pool. A completion never changes loot in an already-running dungeon.

## Author a chest room

1. Create or import a Level Module in the Structure Designer.
2. Build the room and its sealable connections.
3. Aim at the empty cell where the chest should stand, open Module Tools, and use Chest Marker →
   Set from target.
4. Export the module as a format-version-two `.tres` resource.
5. Move the exported resource into the dungeon family's `modules` directory and register it in that
   family's explicit `LevelCatalog`.
6. Add the module ID to a `LevelRoomRequirement` and assign its `chest_loot_pool`.
7. Optionally assign `post_first_completion_chest_loot_pool` for different farm loot after the
   dungeon's first completion.

A module owns at most one chest marker. The marker requires solid support, empty headroom, and at
least one adjacent supported two-cell standing space. It cannot overlap a socket aperture, torch,
player marker, or enemy spawn zone. Catalog validation requires the module marker and the room
requirement's base chest pool to be configured together.

A room requirement may own either an `encounter` or chest loot, never both. This prevents local
enemy spawning in chest rooms. Set the requirement's `count` to the exact number of chest rooms to
generate; every generated copy receives a chest.

## Author a repeat loot pool

Create a `LootPoolDefinition` with a stable unique `id`. Use:

- `independent_rolls` for separately evaluated rewards, each with its own chance; and
- `exclusive_groups` when at most one weighted choice from a group should be awarded.

Each successful independent roll or exclusive group produces at most one stack, so their combined
count is the maximum number of reward stacks the chest can contain. Dungeon chest validation
requires that upper bound to fit the canonical 15-slot chest and that at least one roll or group has
a 100% chance, ensuring every generated chest has loot.

A `LootDropDefinition` references a canonical item and a minimum/maximum count. Counts resolve to
one material stack and cannot exceed that item's stack limit. Equipment has count one and may attach
a `LootEquipmentRollDefinition` with fixed or random affixes and runes. Every equipment result is a
normal canonical item with a unique physical instance ID and captured variant data.

For guaranteed 5–10 Pumpkins plus a 25% Iron Pickaxe bonus, define two independent rolls: a Pumpkin
roll with chance `1.0`, minimum `5`, and maximum `10`; and an Iron Pickaxe roll with chance `0.25`
and count `1`. The 25% check runs independently for each generated chest.

## Add a one-time guaranteed reward

Create a `LevelOneTimeChestRewardDefinition` with:

- a globally unique, stable `reward_id`; and
- a valid `LootBundleDefinition` in `loot_bundle`.

Assign it to `LevelDefinition.one_time_chest_reward` and use LevelDefinition format version five.
The level must contain at least one chest-bearing room. Multiple guaranteed items use multiple
`LootBundleEntryDefinition` values in `fixed_entries`. Set `max_rewards` equal to the number of fixed
entries when the chest must contain exactly that set. A larger reachable `max_rewards` plus
`weighted_candidates` adds random extras without changing the guaranteed entries.

The normal dungeon instance identity is the stable `LevelEntranceDefinition.entrance_id`. Progress
stores that instance ID with the reward ID, so changing either ID creates a different claim identity.
Do not rename released IDs without an explicit save migration.

## Create another dungeon

A hand-authored dungeon needs:

1. format-version-two entry and hallway Level Modules, plus the combat-room and chest-room types it
   uses;
2. a family `LevelCatalog` that explicitly registers those modules and the level;
3. base `LootPoolDefinition` resources and optional post-first-completion pools for chest rooms;
4. a format-version-five `LevelDefinition`, optionally with one guaranteed reward definition;
5. presentation resources; and
6. a `LevelEntranceDefinition` with stable, unique entrance and level IDs.

Omit `one_time_chest_reward` for a purely farmable dungeon. Its chests use repeat pools from the
first run, and a run completes after repeat loot is taken and the player exits alive. Set the field
for a progression dungeon; the guaranteed bundle is claimable once per stable dungeon instance,
while its repeat pools remain farmable.

These contracts also support future procedurally assembled dungeons. A future generator must still
produce valid chest placements from registered modules and supply a stable persisted dungeon
instance ID. Infinite procedural dungeon creation and placement are not implemented yet.

## Stone dungeon example

The current resources are:

- `src/levels/content/dungeons/stone/modules/stone_chest_room.tres` — reusable geometry and chest
  marker;
- `src/levels/content/dungeons/stone/stone_chest_loot.tres` — pre-completion repeat pool;
- `src/levels/content/dungeons/stone/stone_post_completion_chest_loot.tres` — post-completion repeat
  pool;
- `src/levels/content/dungeons/stone/stone_one_time_chest_reward.tres` — guaranteed Iron Pickaxe; and
- `src/levels/content/dungeons/stone/stone_dungeon.tres` — three chest rooms and reward wiring.

On an unclaimed run, one of the three chests contains the Iron Pickaxe and the other two each contain
5–10 Pumpkins. If the player claims the pickaxe and dies, it remains in inventory, its claim remains
recorded, and the dungeon remains incomplete. The next run uses the base Pumpkin pool and requires a
repeat-loot transfer before exit. Beginning with the run after the first completion, all three
chests contain 5–10 Pumpkins and each chest independently has a 25% chance to add one Iron Pickaxe.
Across three chests, the chance of at least one bonus pickaxe is 57.8125%, the expected count is
0.75, and the maximum is three.

The generic `stone_dungeon_one_time_chest_reward` ID remains unchanged. A saved dungeon instance
that already claimed that ID does not receive another guaranteed reward. Iron Pickaxes are ordinary,
discardable inventory items; no provenance or permanent-item rule is attached to them.

## Persistence

Save version fifteen stores `DungeonProgressState` snapshot version one. Each stable dungeon
instance record contains:

- `next_attempt_index`, used to vary repeat loot between runs;
- `completion_count`; and
- sorted `claimed_reward_ids`.

Claims and completion counts are independent: a valid save may contain a claimed reward with zero
completions. The guaranteed seed does not use the attempt index, while repeat seeds do.
Version-thirteen saves first gain empty block emplacements, and version-fourteen saves migrate with
empty dungeon progress. Invalid current progress rejects the load without partially replacing live
state.

## Authoring checklist

- The module is format version two and has exactly one valid chest marker.
- The module is registered in the family catalog and referenced by one room requirement.
- The room requirement has `chest_loot_pool`, an optional post-completion pool, and no `encounter`.
- Every pool, roll, group, choice, bundle, entry, level, entrance, and optional reward has a stable
  unique ID.
- The repeat pool guarantees at least one stack and its worst-case stack count fits the chest.
- The one-time bundle's `max_rewards` is reachable and no greater than chest capacity.
- Equipment drops use count one and valid canonical affix/rune resources.
- A guaranteed-reward level is format version five and contains at least one chest room.
- Direct claim, repeat transfer, full inventory, death, completion, and save round-trip behavior have
  focused tests.
