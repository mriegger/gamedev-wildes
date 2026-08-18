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

Inventory slots contain typed `InventoryStack` objects at runtime. Saves encode each stack as `{item_id, count, socketed_rune_ids}`. The rune IDs are empty for ordinary stacks and preserve the installed runes on each physical gear copy. New worlds begin with every inventory region empty and record the current starter-item migration version so a reload cannot grant legacy items. When a pre-tool save is restored, its one-time migration still preserves every existing stack and inserts the historical starter items when fillable inventory space is available. Previously saved tools remain untouched even when they are no longer granted to new worlds.

## Add a rune

Create a `RuneDefinition` under `src/items/runes/definitions`, assign a stable item ID, icon,
stack size, canonical rarity, compatibility flags, and permanent socket modifiers. Armor-compatible
runes must also declare the supported head, chest, legs, or feet slots. Register the resource in
`src/items/item_catalog.tres`; acquisition remains separate content, such as a canonical crafting
recipe. Rune modifiers do not belong in the inherited selected-item modifier list because they are
activated only through socketed gear.

## Add a mining tool

Create a `MiningActionDefinition` with one or more `MiningToolStat` entries, then assign it as the item's primary action. Each stat has a `StringName` tag, power, and speed multiplier. Blocks declare a mining tag, minimum power, and base duration. A minimum power of zero keeps hand mining available; a positive value requires a matching tool stat.

## Add a tilling tool

Create a `TillingActionDefinition` with canonical source block resources and one canonical result block, then assign it as the item's primary action. The copper hoe maps grass and dirt to dry farmland. Tilling requires the top face, an air block directly above it, and normal interaction reach. The voxel world validates and commits the replacement atomically.

Primary actions currently accept mining, melee, and tilling definitions. Secondary actions currently accept block placement. Catalog validation rejects action types in slots that do not yet have an execution path, and new action types must add their runtime handler and catalog allowance together.

Held items reference a scene through `ItemDefinition.held_scene`. Pixel-art tools can use `PixelExtrudedItem` to turn a square transparent texture into a shaded one-draw-call silhouette mesh with real depth. Custom modeled items can provide any other `Node3D` scene through the same field.

Melee definitions own their held-item attack position and rotation, so different weapons can use different grips without changing the player rig. Switching away from a melee item cancels its presentation before the newly selected tool is rendered.

## Special blocks

Water stays entirely outside the texture and item systems, retaining its dedicated mesh and animated shader unchanged. Torches keep their dedicated renderer and light; the stem uses the assigned wood side texture, the flame uses emissive settings, and the item definition references a dedicated torch inventory icon. The anvil uses a procedural low-poly renderer rather than chunk cube geometry. Its item definition references the project-authored transparent inventory icon; the block definition retains a 16×16 metal texture for shared block validation and targeting presentation.
