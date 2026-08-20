# Textures and items

Block texture source files stay as separate 16×16 PNGs in `src/assets/textures/blocks`. At world startup, `BlockTextureSet` deduplicates the textures referenced by block definitions, generates mipmaps, and builds one `Texture2DArray`. Chunk meshes select a layer per face, so adding a texture never requires editing or regenerating an atlas.

## Add or change a block texture

1. Add the 16×16 PNG to `src/assets/textures/blocks`.
2. Open the block resource in `src/blocks/definitions`.
3. Assign its top, side, and bottom textures. Every chunk-rendered cube requires all three fields, but the same PNG can be assigned to multiple faces.
4. Assign the source texture directly to the matching item definition in `src/items/definitions`.
5. Boot the project and run the world streaming soak. Catalog validation rejects missing or incorrectly sized cube textures, and the soak verifies array layers and mesh attributes.

All terrain texture images must remain 16×16. They are converted to RGBA8 when the runtime array is created. The shader uses nearest-mipmap sampling, while inventory and targeting previews use nearest sampling on the original imported texture.

## Add a block item

Create an `ItemDefinition` resource in `src/items/definitions` with:

- a stable lowercase `StringName` ID that must never be reused for a different item
- an icon texture
- a positive maximum stack size
- the shared unarmed mining action as its primary action
- a `BlockPlacementActionDefinition` secondary action containing the canonical block resource it places

Add the resource to `src/items/item_catalog.tres`. The item catalog derives the reverse block-to-item mapping used by placement UI from the placement action.

Set `BlockDefinition.drop_item_id` to the stable item ID produced by mining. Leave it empty for an intentional no-drop block. Drop data is independent from placement, so future ores, transformed drops, and tool effects do not have to pretend their result places the original block.

The chest block uses 16×16 top, front, and side PNGs, and its inventory icon reuses the exact front
texture so the item matches the placed block. Their 1600×1600 source images were generated with
Meta Muse (`muse-image-1.0-eval`) through the `meta-imagegen` skill, visually inspected, and
downsampled with Lanczos filtering. The final 16×16 textures were simplified into broad, flat pixel
shapes and a limited palette so they remain readable without noisy wood grain. No external source
asset was incorporated. Its north-facing front texture contains the latch, while the other three
vertical faces use the same generated face with only the four centered latch pixels replaced by
neighboring wood and seam pixels, preserving the darker lid and the single lower plank line. Blocks
without a dedicated front texture continue to use their ordinary side texture on all four vertical
faces. The top texture arranges colors sampled from that same lid into three horizontal plank bands.
The lid is color-graded to a medium warm brown that sits between the earlier dark and light
treatments, and the same palette is shared by the front, sides, top planks, and inventory icon.
The dedicated chest renderer uses four 16×16 presentation textures derived from those authored
faces. The matching body front and sides use three lighter plank bands, with the lower latch half
only at the front's top edge. Each body face is an independent quad so no face is layered over a
second box surface. The lid remains a separate box using darker wood, with the upper latch half only
at the front's bottom edge.

## Add a non-block item

Create and register an `ItemDefinition` in the same way. Assign only the actions that the item supports. An item without a placement action can still be stored, stacked, saved, displayed, and dragged, but it does not produce a placement ghost or send an item ID into the voxel world.

Item IDs are `StringName` values at runtime and JSON strings in saves. `BlockId` integers remain limited to world generation, voxel edits, meshing, and world persistence.

Inventory slots contain typed `InventoryStack` objects. Saves encode every stack as
`{item_id, count, equipment_instance}`. Materials use `equipment_instance: null`. Every weapon or
armor stack has count one and an `EquipmentInstance` containing its stable `instance_id`, concrete
affix stat rolls, and ordered `socketed_rune_ids`.

The item ID identifies the shared definition; the instance ID identifies one physical copy. Two
ordinary Copper Swords in the backpack both have item ID `copper_sword`, but each has a different
instance ID. Moving either sword through the hotbar, backpack, equipment slots, a chest, or world
loot preserves that ID and its per-copy data. Instance IDs are allocated monotonically and must be
unique across all of those owners. Do not author or reuse instance IDs in content resources.

New worlds begin with every inventory region empty and record the current starter-item migration
version so a reload cannot grant legacy items. A pre-tool save's one-time migration preserves every
existing stack and inserts the historical starter items only when fillable inventory space is
available. Previously saved tools remain untouched even when they are no longer granted to new
worlds.

## Add equipment

Create an `ItemDefinition`, or an `ArmorDefinition` for armor, and configure:

- the canonical `EquipmentTypeDefinition` from the hierarchy under `src/equipment/types/definitions`
- `max_stack = 1`
- the base actions, stat modifiers, rarity, proficiency, icon, and held or armor presentation the item needs
- an armor slot and optional armor set when using `ArmorDefinition`

Register the item in `src/items/item_catalog.tres`. Runtime factories create the physical
`EquipmentInstance`; the definition remains immutable shared content.

## Add an equipment affix

Create an `EquipmentAffixDefinition` under `src/items/affixes/definitions`. Give it a stable ID and
display-name suffix, list compatible canonical equipment types, set armor-slot flags when it supports
armor, and add one or more `EquipmentAffixStatDefinition` ranges. Register it in the
`equipment_affixes` array of `src/items/item_catalog.tres`.

An affix definition is not a second item. When loot creates equipment, it captures the affix ID and
the concrete amount rolled for every stat on that `EquipmentInstance`. The same `copper_sword`
definition can therefore produce plain, Vicious, Nimble, or combined copies without a separate
variant resource or variant ID. Current affixes support additive or multiplicative numeric stat
rolls.

## Add a rune

Create a `RuneDefinition` under `src/items/runes/definitions`, assign a stable item ID, icon, stack
size, canonical rarity, compatible equipment types, and socket-only stat modifiers. Armor-compatible
runes must also declare the supported head, chest, legs, or feet slots. Register the resource in
`src/items/item_catalog.tres`; acquisition remains separate content, such as a crafting recipe,
enemy loot entry, or dungeon one-time reward. Progression-gated items must be excluded from
unrelated production acquisition paths. Basic Rune currently has no normal production source;
developer spawning remains available for testing and saved copies remain valid. See
[Dungeon chest authoring and rewards](dungeon-chest-authoring.md) for an implemented progression
reward content path.

Socketed rune IDs belong to the physical `EquipmentInstance`. Their array index is the physical
socket index, so fixed loot runes preserve authored order and an empty interior ID preserves an empty
slot. Trailing empty slots are omitted. `InventoryLoadoutCoordinator` activates rune modifiers only
for the selected weapon and equipped armor.

## Add enemy loot

Create a `LootPoolDefinition` under `src/loot/pools` and assign it directly to the relevant
`EntityDefinition`. No separate entity-to-loot table exists.

Use `LootIndependentRollDefinition` for results that each get their own chance. Use
`LootExclusiveGroupDefinition` for a group chance followed by exactly one weighted
`LootWeightedChoiceDefinition`. Every roll, group, and choice needs a stable unique ID. A
`LootDropDefinition` references the canonical item and count range; equipment must have count one and
may attach a `LootEquipmentRollDefinition`. Keyed resolution makes the same pool and defeat seed
produce the same result, and reordering arrays does not change it.

The current `src/loot/pools/zombie.tres` contains:

- an independent 75% roll for 1–3 Copper
- a separate 17% exclusive-group gate with weights 10 plain Copper Sword, 4 rolled-and-runed
  Copper Sword, and 3 Stout Copper Helmet
- one or two equal-weight Vicious/Nimble affixes on the rolled sword, selected without replacement
- one rune slot on that sword containing Power Rune

The gear weights apply only after the 17% group gate succeeds. Copper and gear rolls are independent,
so a defeat may produce neither, either one, or both.

To add one guaranteed Sand to every zombie defeat, add a `LootDropDefinition` referencing
`src/items/definitions/sand_block.tres` with minimum and maximum count one. Wrap it in a
`LootIndependentRollDefinition` with a new stable ID such as `sand` and `chance = 1.0`, then append
that roll to the pool's `independent_rolls`. This does not replace or perturb the keyed Copper and
gear decisions. To make Sand the only possible result, keep only that independent roll and clear the
pool's exclusive groups.

For random affixes, set the minimum and maximum random-affix counts and add weighted
`LootAffixChoiceDefinition` resources. Selection removes each chosen affix, so one copy cannot roll
the same affix twice. For random runes, set `random_rune_slot_count` and add weighted
`LootRuneChoiceDefinition` resources. Every slot samples the full choice set independently, so
multiple slots may receive the same rune. All configured choices must be compatible with every slot
they may fill.

For fixed special gear, set `fixed_affixes` and `fixed_runes` instead. Fixed rune array order is
socket order. Give an affix stat equal minimum and maximum amounts when the special result needs an
exact value rather than a range. This still creates the canonical base item with a unique instance
ID and captured per-copy data. Create a separate `ItemDefinition` only when the special weapon
genuinely needs its own stable content identity, action, visuals, or base values.

Affixes and runes currently change numeric stats; there is no generic flame, knockback, or arbitrary
trait payload. A new behavior family must add its typed definition, executor, validation, and a real
combat caller together before loot can author that behavior.

## World-loot lifetime and persistence

`WorldLootState` owns at most 128 entries with stable monotonic entry IDs. Material drops merge with
nearby same-item stacks within 1.5 blocks, refresh their remaining lifetime when merged, and expire
after five minutes of active overworld simulation. Equipment never merges or expires. At capacity,
the material entry nearest expiration is evicted first. If every retained entry is equipment, the
oldest equipment entry is evicted so a new validated batch cannot permanently deadlock loot drops.

Streaming controls drop views, not gameplay state. An unloaded drop reappears when its position is
ready again. Material pickup can fill available inventory space partially while leaving the remainder
under the same world entry ID. Equipment pickup is all-or-none. World loot was introduced in save
version thirteen; current version-fifteen saves persist entry IDs, positions, remaining material
lifetimes, complete stacks, and the next world-entry ID alongside block emplacements and dungeon
progress.

## Add a mining tool

Create a `MiningActionDefinition` with one or more `MiningToolStat` entries, then assign it as the item's primary action. Each stat has a `StringName` tag, power, and speed multiplier. Blocks declare a mining tag, minimum power, and base duration. A minimum power of zero keeps hand mining available; a positive value requires a matching tool stat.

The Iron Pickaxe uses the canonical `pickaxe` tag with power 3 and a 2.5 speed multiplier. It is
registered as a single-stack non-block item with its own icon and held presentation. Its initial
normal acquisition is the stone dungeon's guaranteed reward; after that dungeon's first completion,
each repeat chest independently has a 25% chance to contain another. No crafting recipe or ordinary
enemy loot pool references it.

## Add a tilling tool

Create a `TillingActionDefinition` with canonical source block resources and one canonical result block, then assign it as the item's primary action. The copper hoe maps grass and dirt to dry farmland. Tilling requires the top face, an air block directly above it, and normal interaction reach. The voxel world validates and commits the replacement atomically.

Primary actions currently accept mining, melee, tilling, and held bow-draw definitions. Secondary actions accept
block placement and consumption. Catalog validation rejects action types in slots that do not yet
have an execution path, and new action types must add their runtime handler and catalog allowance
together.

Held items reference a scene through `ItemDefinition.held_scene`. Pixel-art tools can use `PixelExtrudedItem` to turn a square transparent texture into a shaded one-draw-call silhouette mesh with real depth. Custom modeled items can provide any other `Node3D` scene through the same field.

The bow and its stone and copper arrows use project-authored low-poly primitive scenes. The bow's
scene origin is its wrapped grip and cancels the hand socket's resting pitch so it rests across the
right hand with its string side facing up. Their transparent 16×16 icons use deterministic hard-edged pixel
silhouettes with bounded palettes; the arrow variants share one silhouette and differ at the head.
The bow's primary action owns its quick raise duration, 1.5-second draw duration, launch-speed
range, and ordered canonical ammunition definitions. Holding primary use keeps the draw state active,
while the humanoid animator poses both arms and the held bow view bends its two string segments around
the first available stone or copper arrow. A player-relative billboard presents the current draw
progress with a black background and yellow fill. A translucent white trajectory line uses the
runtime's current draw-scaled ballistic prediction, fading from 30 to 95 percent of the path before
the first contact. The player interaction state resolves the first voxel surface under the live cursor,
falling back to the ground plane, and the bow action adjusts its launch angle as speed increases to hit that point when possible while
never raising beyond 45 degrees. Releasing commits one ammunition removal before `ArrowProjectileRuntime`
launches the matching model from the same authoritative transform. The bounded runtime evaluates gravity, sweeps fixed flight segments against entity bounds and voxel raycast solids,
aligns the arrow with its velocity, presents a short fading trail from bounded recent flight samples,
and owns its one-second impact hold and fade cleanup. Projectile
profiles own pierce damage, knockback, collision radius, gravity, and lifetime values; committed hits
flow through combat affinity resolution, enemy hit reactions, damage feedback, particles, and bow
proficiency.

Melee definitions own their idle and attack transforms, animation style, two-handed stance, and optional impact-effect radius. The copper sword's one-handed alternating swing renders a procedural radial scan from the player to its profile's full sweep and reach, while the copper hammer holds a custom modeled handle in both hands, raises it overhead, and drives it into a procedural shockwave without adding weapon-specific branches to inventory selection. Switching away from a melee item cancels its presentation before the newly selected tool is rendered.

## Special blocks

Water stays entirely outside the texture and item systems, retaining its dedicated mesh and animated
shader unchanged. Torches keep their dedicated renderer and light; the stem uses the assigned wood
side texture, the flame uses emissive settings, and the item definition references a dedicated torch
inventory icon. The anvil and cauldron use procedural low-poly renderers rather than chunk cube
geometry. Their item definitions reference project-authored, transparent 16×16 pixel-art icons; the
health potion uses the same hard-edged project-authored icon treatment. The station block definitions
retain a 16×16 metal texture for shared block validation and targeting presentation.
