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

Add the resource to `src/items/item_catalog.tres`. The item catalog derives the reverse block-to-item mapping from the placement action, so placement and mined drops cannot drift into separate mappings.

## Add a non-block item

Create and register an `ItemDefinition` in the same way. Assign only the actions that the item supports. An item without a placement action can still be stored, stacked, saved, displayed, and dragged, but it does not produce a placement ghost or send an item ID into the voxel world.

Item IDs are `StringName` values at runtime and JSON strings in version 3 saves. `BlockId` integers remain limited to world generation, voxel edits, meshing, and world persistence.

Inventory slots contain typed `InventoryStack` objects at runtime. Version 3 saves keep the same `{item_id, count}` JSON shape. When a pre-tool save is restored, the inventory preserves every existing stack and inserts the starter copper pickaxe into an available hotbar slot.

## Add a mining tool

Create a `MiningActionDefinition` with one or more `MiningToolStat` entries, then assign it as the item's primary action. Each stat has a `StringName` tag, power, and speed multiplier. Blocks declare a mining tag, minimum power, and base duration. A minimum power of zero keeps hand mining available; a positive value requires a matching tool stat.

Held items reference a scene through `ItemDefinition.held_scene`. Pixel-art tools can use `PixelExtrudedItem` to turn a square transparent texture into a shaded one-draw-call silhouette mesh with real depth. Custom modeled items can provide any other `Node3D` scene through the same field.

## Special blocks

Water stays entirely outside the texture and item systems, retaining its dedicated mesh and animated shader unchanged. Torches keep their dedicated renderer and light; the stem uses the assigned side texture, the flame uses emissive settings, and the inventory icon comes from its item definition.
