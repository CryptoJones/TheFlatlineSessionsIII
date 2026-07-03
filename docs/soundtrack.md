# Original Soundtrack

First soundtrack pass generated 2026-07-02 from CJ's local licensed sample
library on pluto (`/mnt/hdd1/Samples/packs`). Tracks are loopable Ogg Vorbis
assets for in-game playback.

Distribution note: before shipping a public build, verify the upstream sample
pack licenses permit redistribution as rendered game music.

## Album

**The Flatline Sessions III: Mona Lisa Underdrive - Original Soundtrack**

## Game Cues

| Cue | File | Duration |
|---|---|---:|
| Title | `assets/audio/music/title.ogg` | 1:14 |
| Streets fallback | `assets/audio/music/streets.ogg` | 1:14 |
| Shops | `assets/audio/music/shops.ogg` | 1:14 |
| Cyberspace | `assets/audio/music/cyberspace.ogg` | 1:14 |
| ICE combat | `assets/audio/music/ice_combat.ogg` | 1:14 |

## Chapter Tracks

| Chapter | Track | File | Duration |
|---|---|---|---:|
| 01 | The Smoke | `ch01_the_smoke.ogg` | 1:32 |
| 02 | Dog Solitude | `ch02_dog_solitude.ogg` | 1:32 |
| 03 | Florida | `ch03_florida.ogg` | 1:32 |
| 04 | Malibu | `ch04_malibu.ogg` | 1:32 |
| 05 | The Oracle of Lost Technology | `ch05_oracle_lost_tech.ogg` | 1:32 |
| 06 | The Work | `ch06_the_work.ogg` | 1:32 |
| 07 | The Aleph | `ch07_the_aleph.ogg` | 1:32 |
| 08 | The Loa's Price | `ch08_the_loas_price.ogg` | 1:32 |
| 09 | Underground | `ch09_underground.ogg` | 1:32 |
| 10 | The Switch | `ch10_the_switch.ogg` | 1:32 |
| 11 | The Siege of Dog Solitude | `ch11_siege_dog_solitude.ogg` | 1:32 |
| 12 | Mona Lisa Underdrive | `ch12_mona_lisa_underdrive.ogg` | 1:32 |

`AudioManager` maps normal exploration to the active chapter track. Explicit
room music still wins, shops use `shops`, and matrix/ICE views use their
specialized cues.
