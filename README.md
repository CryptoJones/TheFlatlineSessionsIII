# The Flatline Sessions III — Mona Lisa Overdrive

A fan-made, modern-look adventure after William Gibson's **Mona Lisa Overdrive** — the
third game in the Flatline Sessions trilogy, completing the arc begun by
[The Flatline Sessions](../neuromancer-godot) (the 2026 remaster of Interplay's 1988
*Neuromancer*) and continued by
[The Flatline Sessions II — Count Zero](../TheFlatlineSessionsII). Renders clean at a
**native 1920×1080 canvas in full 32-bit color**.

## The shape of the game

*Mona Lisa Overdrive* braids four viewpoint characters, so the game does too. Twelve
chapters, played in novel order, each locking you to one PoV:

| # | Chapter | You play |
|---|---------|----------|
| 01 | The Smoke | Kumiko Yanaka |
| 02 | Dog Solitude | Slick Henry |
| 03 | Florida | Mona |
| 04 | Malibu | Angie Mitchell |
| 05 | The Oracle of Lost Technology | Kumiko Yanaka |
| 06 | The Work | Mona |
| 07 | The Aleph | Slick Henry |
| 08 | The Loa's Price | Angie Mitchell |
| 09 | Underground | Kumiko Yanaka |
| 10 | The Switch | Mona |
| 11 | The Siege of Dog Solitude | Slick Henry |
| 12 | Mona Lisa Overdrive | Angie Mitchell |

Each chapter has its own room graph, main quest, NPCs, and starting kit. Finishing a
chapter unlocks the next. Matrix access varies by PoV: Slick jacks in through the
Factory trodes, Angie *is* the interface (cortical lace), Kumiko borrows Tick's rig,
and Mona stays in the meat.

## Status

**Playable scaffold with generated art pass.** The whole story is playable end to end.
All dialog, quests, items, shops, and matrix targets are in place, written in the novel's
tone — our own prose throughout.

The first full art pass is in `assets/backgrounds_hd/` and `assets/cyberspace/`: heavily
rotoscoped, painted-over-live-action plates with graphic-novel realism, flattened color
planes, visible ink contours, warm 35mm grain, and violet/magenta cyberpunk accents. See
[`docs/art-style-prompt.md`](docs/art-style-prompt.md) for the locked style prompt.

For review from a tablet/phone, see
[`docs/The_Art_of_The_Flatline_Sessions_III.pdf`](docs/The_Art_of_The_Flatline_Sessions_III.pdf).

## Run it

```sh
./run.sh            # imports assets, launches (software GL by default on Linux)
GPU=1 ./run.sh      # force GPU rendering
```

Requires Godot 4.3+. Keyboard: WASD/arrows move, I inventory, Q quest log, F5/F9 quick
save/load, Esc backs out of menus.

## Validate the scaffold

```sh
godot --headless --path . --script res://tests/validate_data.gd
```

Checks every chapter, room graph, exit, NPC dialog graph, quest flag, item, and shop
reference. Run it after any data edit.

## Layout

```
data/chapters.json        chapter spine (PoV, rooms file, quest, intro/outro, start kit)
data/quests.json          one flag-driven quest per chapter
data/rooms/chNN_*.json    per-chapter room graphs
data/npcs/*.json          branching dialog (set_flag / grant / credits / require_flag)
data/items.json           item catalog     data/shops.json  shops
data/cyberspace/*.json    matrix targets (per-chapter, ICE-rated)
data/pax/*.json           NET news + boards
src/                      engine (see src/core/Game.gd)
```

## Credits

Fan project after the novel *Mona Lisa Overdrive* by William Gibson. Game code and all
in-game prose are original to this project. Copyright **CryptoJones**
<cryptojones@owasp.org>; engine shared with The Flatline Sessions.
