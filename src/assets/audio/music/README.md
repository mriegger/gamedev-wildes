# Music – Wildes

Background music is streamed on the `Music` bus. Each subfolder holds a themed
pool of tracks that are shuffled at runtime with a randomized gap between plays.

- `music/daytime/` — soft daytime overworld tracks. Audible only during daytime
  (`6:00-19:00` with sunrise/sundown fade) and ducked during combat.
- `music/dungeon/` — repeatable dungeon tracks with randomized gaps. Dungeon
  music is independent of the day clock and remains audible during combat.
- Future pools (e.g. `music/night/`) should follow the same layout: one folder
  per context.

Drop audio files into the appropriate folder and assign them to the
appropriate playlist array. Prefer 48 kHz,
`loop=false` for scored tracks, and keep loudness gentle — the player applies
a soft base gain on top of the `Music` bus and the `music_volume` setting.

Document every added file only in the root `src/assets/audio/README.md` attribution table.
