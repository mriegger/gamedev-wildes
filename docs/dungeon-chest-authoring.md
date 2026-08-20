# Dungeon chest authoring and rewards

Dungeon chests are generated content, not persistent overworld containers. A Level Module supplies
the physical chest marker, its `LevelRoomRequirement` supplies the repeat loot bundle, and its
`LevelDefinition` may supply one dungeon-wide first-clear reward. This keeps room geometry reusable:
the same chest-room module can serve a story dungeon, a farmable dungeon, or a future generated
dungeon without embedding reward rules in the geometry resource.

## Runtime rules

Every generated room whose module has a chest marker contains one physical chest. Chest rooms are
passive rooms: they do not create a local enemy wave or a branch seal. They are not safe
rooms; enemies from another room use the same dungeon navigation and may enter and attack the
player. Dungeon chests are take-only and disappear with the attempt runtime, so players cannot use
them as persistent storage.

When a level has an unclaimed `LevelOneTimeChestRewardDefinition`:

- one generated chest is selected deterministically from all chest placements;
- that chest contains only the first-clear bundle for the attempt;
- every other chest contains its room requirement's repeat bundle;
- failed attempts select the same first-clear chest and resolve the same first-clear contents; and
- after the reward is claimed, every chest uses repeat loot on later attempts.

Taking first-clear items moves them into attempt-owned escrow rather than the player inventory. The
player completes the first clear only by emptying that chest and using the return door while alive.
Exit commits the complete escrow, reward claim, and completion count together. A partial chest does
not complete the dungeon. Death, quitting, or leaving without completing destroys the runtime and
its escrow, leaving the reward unclaimed for the next attempt.

First-clear transfers validate capacity for the complete pending escrow. If the inventory cannot
hold it, the requested transfer remains unchanged and the game displays
`Inventory full — drop items first`.
Capacity is checked again at the return door because the player may fill slots after taking the
reward. A failed exit remains in the dungeon with the escrow intact so the player can drop items
and retry.

Repeat loot moves directly into inventory. A later run increments its completion count when the
player takes at least one repeat reward and exits alive. Leaving without repeat loot is allowed but
does not add a completion. Repeat loot already in inventory survives death, quit, or abandon; the
resulting take-loot-and-die farming loop is an accepted current rule.

Enemy clearance is not a completion condition today. The completion transaction is intentionally
focused on reward collection and alive exit. If an all-enemies-defeated rule is added later, it must
be supplied by the encounter state owner and validated as another input to that transaction.

## Author a chest room

1. Create or import a Level Module in the Structure Designer.
2. Build the room and its sealable connections.
3. Aim at the empty cell where the chest should stand, open Module Tools, and use Chest Marker →
   Set from target.
4. Export the module as a format-version-two `.tres` resource.
5. Move the exported resource into the dungeon family's `modules` directory and register it in that
   family's explicit `LevelCatalog`.
6. Add the module ID to a `LevelRoomRequirement` whose `chest_loot_bundle` is set.

A module owns at most one chest marker. The marker requires solid support, empty headroom, and at
least one adjacent supported two-cell standing space. It cannot overlap a socket aperture, torch,
player marker, or enemy spawn zone. Catalog validation requires the module marker and the room
requirement's `chest_loot_bundle` to be configured together.

A room requirement may own either `encounter` or `chest_loot_bundle`, never both. This is why chest
rooms create no local enemies. Set the requirement's `count` to the exact number of chest rooms to
generate; every generated copy receives a chest.

## Author a loot bundle

Create a `LootBundleDefinition` with a stable unique `id`. Its fields are:

- `max_rewards`: the maximum number of resolved entries, and therefore the maximum number of chest
  stacks;
- `fixed_entries`: guaranteed `LootBundleEntryDefinition` entries; and
- `weighted_candidates`: optional `LootWeightedChoiceDefinition` entries.

The resolver chooses the final entry count inclusively from
`max(1, fixed_entries.size())` through `max_rewards`. It includes every fixed entry, then selects the
remaining weighted candidates without replacement. `max_rewards` is not the number of random draws.
It is the upper bound on the chest's resolved stacks. It must not exceed the canonical chest's
15-slot capacity, and enough distinct fixed-plus-weighted entries must exist to reach it.

Each entry owns a stable ID and one `LootDropDefinition`. A drop references a canonical item and a
minimum/maximum count. Counts resolve to one material stack and cannot exceed that item's stack
limit. Equipment has count one and may attach a `LootEquipmentRollDefinition` with either fixed or
random affixes and either fixed or random runes. Every equipment result is a normal canonical item
with a unique physical instance ID and captured variant data.

To guarantee multiple items, put each item in `fixed_entries`. Set `max_rewards` equal to the number
of fixed entries when the chest should contain exactly that set. To guarantee those items and add
random extras, set a larger reachable `max_rewards` and add weighted candidates.

## Add a first-clear reward

Create a `LevelOneTimeChestRewardDefinition` with:

- a globally unique, stable `reward_id`; and
- a valid `loot_bundle`.

Assign it to `LevelDefinition.one_time_chest_reward` and use LevelDefinition format version four.
The level must contain at least one chest-bearing room. Multiple guaranteed first-clear items use
multiple fixed entries in this bundle; they do not require additional chest-room geometry.

The normal dungeon instance identity is the stable `LevelEntranceDefinition.entrance_id`. Progress
stores that instance ID with the reward ID, so changing either ID creates a different claim identity.
Do not rename released IDs without an explicit save migration.

Progression-gated items must be absent from unrelated production acquisition paths. A guaranteed
Iron Pickaxe does not gate progression if the same pickaxe remains in a crafting recipe or ordinary
enemy pool. Developer-console spawning is intentionally outside production progression rules.

## Create another dungeon

A hand-authored dungeon needs these content resources:

1. format-version-two entry and hallway Level Modules, plus the combat-room and chest-room types the
   dungeon uses;
2. a family `LevelCatalog` that explicitly registers those modules and the level;
3. repeat `LootBundleDefinition` resources for chest-bearing room requirements;
4. a format-version-four `LevelDefinition`, optionally with one first-clear reward definition;
5. presentation resources; and
6. a `LevelEntranceDefinition` with stable, unique entrance and level IDs.

Omit `one_time_chest_reward` for a purely farmable dungeon. Its chests use repeat pools from the
first run, and a run completes after repeat loot is taken and the player exits alive. Set the field
for a progression dungeon; its first clear uses the guaranteed bundle and later runs become
farmable automatically.

The loot, chest, and progress contracts also support future procedurally assembled dungeons. That
future generator must still produce valid chest placements from registered modules and pass a
stable generated dungeon-instance ID to progress. A permanent world entrance can keep its authored
entrance ID. A dynamically created instance needs a persisted ID derived from its durable world
identity, not a scene path, display name, or per-run random value. Infinite procedural dungeon
creation and placement are not implemented yet.

## Stone dungeon example

The current resources are:

- `src/levels/content/dungeons/stone/modules/stone_chest_room.tres` — reusable geometry and chest
  marker;
- `src/levels/content/dungeons/stone/stone_chest_loot.tres` — repeat pool;
- `src/levels/content/dungeons/stone/stone_one_time_chest_reward.tres` — first-clear Iron Pickaxe; and
- `src/levels/content/dungeons/stone/stone_dungeon.tres` — three chest rooms and reward wiring.

On an unclaimed run, one of the three chests deterministically contains the Iron Pickaxe and each of
the other two contains exactly one 5–10 Pumpkin stack. After the Iron Pickaxe is secured by an alive
exit, all three chests use that Pumpkin repeat bundle on later attempts. The Iron Pickaxe is a
power-3 mining tool with a 2.5 speed multiplier and has no crafting recipe or ordinary enemy-loot
source.

The generic `stone_dungeon_one_time_chest_reward` ID remains unchanged. A saved dungeon instance
that already claimed that ID does not receive another first-clear reward after the content changes to
Iron Pickaxe. Basic Rune now has no normal production acquisition; developer spawning remains a
debug path, and existing saved copies remain valid.

## Persistence

Save version fifteen stores `DungeonProgressState` snapshot version one. Each stable dungeon
instance record contains:

- `next_attempt_index`, used to vary repeat loot between runs;
- `completion_count`; and
- sorted `claimed_reward_ids`.

The first-clear seed does not use the attempt index, so failed attempts preserve its chest and
contents. Repeat seeds do use the persisted attempt index, so later attempts resolve independently.
Version-thirteen saves first gain empty block emplacements, and version-fourteen saves migrate with
empty dungeon progress. Invalid current progress rejects the load without partially replacing live
state.

## Authoring checklist

- The module is format version two and has exactly one valid chest marker.
- The module is registered in the family catalog and referenced by one room requirement.
- The room requirement has `chest_loot_bundle` and no `encounter`.
- Every bundle, entry, choice, level, entrance, and optional reward has a stable unique ID.
- `max_rewards` is at least one, reachable, and no greater than chest capacity.
- Equipment drops use count one and valid canonical affix/rune resources.
- A first-clear level is format version four and contains at least one chest room.
- A progression-gated item has no unintended crafting or production-loot bypass.
- First-clear, repeat, full-inventory, death, and save round-trip behavior have focused tests.
