# Art regeneration candidates — 2026-07-31 / 2026-08-01

Recovered from `makemake:~/.buzz-dev/.scratch/` on 2026-08-13. This work existed on
exactly one disk with no remote; it is archived here so it survives.

**No game asset has been replaced by this commit.** Everything here is review
material sitting alongside the shipping plates, awaiting a keep/regenerate ruling.

## What's here

| dir | contents |
|-----|----------|
| `full_regen/` | the 127-plate batch regeneration + a fresh SHA256 manifest |
| `candidates/` | the 17 regenerated candidates, normalized to 1344×768, + a fresh SHA256 manifest |
| `fixes/` | the 7 round-3 fix plates, with `superseded/` holding their round-1/round-2 versions |
| `round1_rejected/` | the 8 round-1 versions that were rejected and regenerated |
| `round2_rejected/` | the 2 round-2 versions (R06, R11) rejected a second time |
| `apply_plan.json` | the 144-entry plan mapping every plate to its destination |
| `packets/` | the review PDFs — the two generated on makemake, plus the full 144-plate review |

## The apply plan

`apply_plan.json` is the authoritative record: 144 entries, 139 into
`assets/backgrounds_hd/` and 5 into `assets/cyberspace/`, no duplicate destinations.
Verified 2026-08-13 on ronin28: all 144 sources resolve, all 144 SHA256s match, and
every destination already exists in the repo — this plan replaces plates, it never
invents one.

| origin | count |
|--------|-------|
| `batch regen` | 120 |
| `approved R01` … `approved R17` | 17 |
| `round-3 fix` | 7 |

The R-slots are marked *approved* because they already cleared the consensus gate
(three reviews, two-thirds ACCEPT, no unresolved blocker) before the plan was
written. Nothing was ever applied.

## Slot → target plate

| slot | replaces | defect in the shipping plate |
|------|----------|------------------------------|
| R01 | `K1_market.png` | pseudo-text and people in an environment-only market |
| R02 | `K5_street.png` | human figure and label fragments violate the locked empty-room prompt |
| R03 | `K5_noodles.png` | prominent pseudo-text in neon, menus, and posters |
| R04 | `K5_walk.png` | crowd and pseudo-signage disrupt the quiet environment-only shot |
| R05 | `K9_brixton.png` | fake neon wordmark where the prompt allows abstract glow only |
| R06 | `M3_squat.png` | letter-like writing where only diagrammatic scribbles are allowed |
| R07 | `CH01_intro_03.png` | guest room reused before the arrival vehicle has stopped |
| R08 | `CH01_outro_02.png` | K9 Kensington landing reused in Chapter 1's K1 Notting Hill sequence |
| R09 | `CH05_intro_02.png` | pseudo-text around the Finn shrine distracts from the story beat |
| R10 | `CH05_intro_03.png` | pseudo-word signs contaminate the Finn/oracle approach |
| R11 | `CH05_outro_01.png` | noodle counter reused for the Finn's alley shrine |
| R12 | `CH06_outro_01.png` | mirror overlay became a giant disembodied head in a monitor/tank |
| R13 | `CH07_outro_01.png` | adult Bobby/Count became a child with a telescope in a lab |
| R14 | `CH08_outro_01.png` | Mamman Brigitte lacked loa-specific widow/death identity |
| R15 | `CH10_intro_02.png` | Mona, the centered female viewpoint character, was absent |
| R16 | `CH11_outro_01.png` | Hydraulic Judge became a bleeding humanoid Terminator |
| R17 | `CH12_outro_03.png` | Mona's Sense/Net future became an empty code-screen studio |

## Manifest note

The manifest that shipped with the original folder was stale: 9 of its 17 hashes
matched the files, and 8 (R02, R06, R10, R11, R12, R14, R16, R17 — exactly the
round-1 rejected slots) matched nothing on disk anywhere. Those 8 were regenerated
in place after the manifest was written and it was never rewritten. The manifest in
`candidates/` is freshly generated from the files archived here.

## Provenance of the three art passes

| pass | date | fate |
|------|------|------|
| `feature/hidden-anti-hack-room` re-render | 2026-07-03 | superseded — all 21 of its plates were replaced on main by `fcbba3e` / `c452f6e` |
| main (shipping in v1.2.5) | 2026-07-24 | current |
| these candidates | 2026-07-31 → 08-01 | unmerged, awaiting ruling |
