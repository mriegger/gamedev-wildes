# Audio Assets – Wildes

Audio for ambient atmosphere (birds day + insects night) + footsteps + tool impacts.

Structure:
- `ambient/` – 2D background birds chirping (continuous loop day-only per current plan, previously random bursts)
  - `birds/nri-DawnchorusinAmphitheater.mp3` or `ambient/nri-...mp3` – Source: National Park Service – Dawn chorus (Public Domain)
  - `insects/` – placeholder for night insects
- `footsteps/` – 2D (MVP) positioned, simple always-on dirt for now via PlayerFootsteps
  - `dirt/` – 9x Footstep_Dirt_*.wav (CC BY 4.0)
  - `grass/sand/stone/wood/leaves/` – placeholder
- `sfx/tools/` – tool impact clunks for digging
  - `impactGeneric_light_001..004.ogg` – 4x generic light impacts (Kenney CC0) – used as pickaxe/axe hit on terrain

Godot 4.7 will generate `.import` files next to each ogg/wav/mp3 – commit them.

Surface mapping is defined in `src/audio/footstep_catalog.gd` (BlockId → surface string) – future for surface-aware footsteps.

## Attribution

| File | Source | License | Notes |
| --- | --- | --- | --- |
| `ambient/nri-DawnchorusinAmphitheater.mp3` | National Park Service – Dawn chorus in Amphitheater | Public Domain (U.S. Government) | Dawn chorus, now continuous loop day-only |
| `footsteps/dirt/Footstep_Dirt_01.wav` to `Footstep_Dirt_09.wav` (9 files) | Fantasy Sound Effects Library – Footstep Dirt – by Morten Barfod Søegaard, Little Robot Sound Factory – https://littlerobotsoundfactory.com/ | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) | Original source: Little Robot Sound Factory. No changes beyond file placement. |
| `sfx/tools/impactGeneric_light_001.ogg` to `impactGeneric_light_004.ogg` (4 files) | [Impact Sounds](https://kenney.nl/assets/impact-sounds) – Kenney (https://kenney.nl) – generic light impacts | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) | No attribution required per CC0, but documented here. Used as pickaxe/axe clunk on terrain. Original source: Kenney.nl |

**License compliance:**
- CC BY 4.0: Credit author, link to license, indicate if changed.
- CC0 1.0: No attribution required, but we document source for transparency.
- Public Domain NPS: Best practice attribution "Source: National Park Service".

Also update main `README.md` → Assets & Attribution table when adding new third-party audio.



