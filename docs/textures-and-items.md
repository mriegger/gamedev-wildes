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
- the canonical `BlockDefinition` resource it places

Add the resource to `src/items/item_catalog.tres`. The item catalog derives the reverse block-to-item mapping from the same `placed_block` reference, so placement and mining cannot drift into separate mappings.

## Add a non-block item

Create and register an `ItemDefinition` in the same way, but leave `placed_block` empty. It can be stored, stacked, saved, displayed, and dragged. Selecting it does not produce a placement ghost or send an item ID into the voxel world.

Item IDs are `StringName` values at runtime and JSON strings in version 3 saves. `BlockId` integers remain limited to world generation, voxel edits, meshing, and world persistence.

## Special blocks

Water stays entirely outside the texture and item systems, retaining its dedicated mesh and animated shader unchanged. Torches keep their dedicated renderer and light; the stem uses the assigned side texture, the flame uses emissive settings, and the inventory icon comes from its item definition.
