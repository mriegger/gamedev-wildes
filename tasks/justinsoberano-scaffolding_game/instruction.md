# Task 000 - Scaffold for Wildes

## Goal
Build a poilished isometric 3D sandbox game. The player explored one continouous 200x200 world, mines terrain and builds freely.

## Requirements
### One current world
Generate from a random seed. Place spawn in an open meadow near trees and exposed stone. farther terrain forms sandy lowlands, wooded rises, and stone ridges, roling elevation, and occasional overlooks. Grass dirt, stone, sand, wood, and leaves are collectible and placeable blocks.

Use crisp cubes with subtle variation, add readable face shadow and strong block  silhuoettes. Rendering, walkable surfaces, targeting, mined material, and occupancy must agree on the current world. 

Use a 3D orthographic isometric camera and add a blocky explorer character. Controls are camera relative, WASD, space to hop, Q/E for 45 degree turns, and scrolling zoom. Following and rotation is smooth. The player cannot travel beyond the boundary, we should show a haze effect on the world edge. 

### Blocks
Add a yellow outline to reachable blocks and a ghost preview of the block when a block is in the players selected inventory slot. Hold left mouse to mine, and right to place. If the player is holding a block but is holding left, show the yellow outline instead since the player is mining, otherwise we show a ghost block for the block they are holding in their hotbar. 

Keys 1-9 select that slot in the inventory. Only when the player has a block in their inventory slot they can place and it removes one from the inventory. An occupied block, out of reach, world edge, plyer overlap, empty inventory, or a block destination that changed without commitment will reject without consumption. 

The player has a 6 block radius of mining and placing.

### Mining and placing
Mining progress belongs to the one targeted block. Releasing early, changin aim, leaving reach, opening an overlay, changing that block, etc. cancels it. When mining a block we show a block pulse effect. The user can mine the blocks at the cursor's position, just making sure that the block is inside of the player's 6 block radius.

### Hotbar
Show a nine slot swatch hotbar, the inventory, with number keys and counts of the materials if there is one in that slot.

## Technical Constraint
- Implement in Godot 4.7
- Keep all files inside of src/
- Keep all terrain responsive.
- Keep the world finite and session local. 

## Acceptale Criteria
- The game can be launched, there are no errors or warnings
- The user can see the game, the camera is not bugged or inside of blocks. 