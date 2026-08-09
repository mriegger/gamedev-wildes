# Audio Assets – Wildes

Audio for ambient birds (2D day-only) + surface-aware footsteps (3D).

Structure:
- `ambient/` – 2D background birds chirping (day-only, random bursts)
  - `nri-DawnchorusinAmphitheater.mp3` – Source: National Park Service – Dawn chorus (Public Domain)
- `footsteps/` – 3D positioned at foot markers, surface-aware via FootstepCatalog
  - `dirt/` – 9x Footstep_Dirt_*.wav (CC BY 4.0, see attribution)
  - `grass/` – placeholder
  - `sand/` – placeholder
  - `stone/` – placeholder
  - `wood/` – placeholder
  - `leaves/` – placeholder

Godot 4.7 will generate `.import` files next to each ogg/wav/mp3 – commit them.

Surface mapping is defined in `src/audio/footstep_catalog.gd` (BlockId → surface string).

## Attribution

| File | Source | License | Notes |
| --- | --- | --- | --- |
| `ambient/nri-DawnchorusinAmphitheater.mp3` | National Park Service – Dawn chorus in Amphitheater | Public Domain (U.S. Government) | Dawn chorus recorded in Amphitheater |
| `footsteps/dirt/Footstep_Dirt_01.wav` to `Footstep_Dirt_09.wav` (9 files) | Fantasy Sound Effects Library – Footstep Dirt – by Morten Barfod Søegaard, Little Robot Sound Factory – distributed by Little Robot Sound Factory (https://littlerobotsoundfactory.com/) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) | Original source: Little Robot Sound Factory. No changes made beyond file placement. |

**CC BY 4.0 compliance:** Credit author (Morten Barfod Søegaard, Little Robot Sound Factory), link to license, indicate no modifications beyond trimming/placement if applicable. Keep this table updated when adding surfaces.

Also update main `README.md` → Assets & Attribution table when adding new third-party audio.


