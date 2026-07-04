# Changelog

All notable changes to **The Flatline Sessions III — Mona Lisa Underdrive** are
documented here. This project adheres to [Semantic Versioning](https://semver.org).

## [1.0.4] — 2026-07-03

### Added
- **Give Hint.** A "? Give Hint" button (and the `H` key) in every room maps the
  compass route to your current objective and names the action to take.
- **Endgame.** Finishing the final chapter now plays a finale card (THE END + a
  closing coda) before returning to the title.

### Changed
- **Deck detection.** `_has_deck()` now also recognises a deck-flagged software
  item, so a borrowed/patched deck can enable Jack In (parity with II's fix).
- **Action-bar declutter.** A finished conversation drops its Talk button, kept
  only when the current objective still needs that NPC.

## [1.0.3] — 2026-07-03

### Added
- **Dedication loading card.** Every boot opens on a quiet fade-in dedication to
  William Gibson before the title; any key or click skips it.
- **Autosave (on by default).** A rolling `Autosave` slot refreshed at every room
  entry and on chapter completion, so progress survives without opening the Save
  menu. Toggle it in Settings; it's remembered between runs and listed in Load.

### Changed
- **Title screen reworked.** The game title (*THE FLATLINE SESSIONS III* / *MONA
  LISA UNDERDRIVE*) now renders outlined at the top and will full-bleed a cover
  plate the moment `assets/ui/cover.png` is added (art still pending for III).
- **Fixed compass.** The W/N/S/E controls appear in every room; directions that
  aren't real exits are dimmed and unclickable rather than vanishing, so the
  layout no longer shifts room to room.
