#!/usr/bin/env bash
# Self-contained launcher — zero manual steps, ever.
#  - Always imports assets first (incremental); if the cache is stale/corrupt it
#    wipes .godot and rebuilds, so a fresh clone or a `git pull` never black-screens.
#  - On Linux it defaults to SOFTWARE rendering (llvmpipe) so it draws correctly
#    on low-end / GPU-less boxes. Force the GPU: `GPU=1 ./run.sh`.
# Usage: ./run.sh [extra godot args]   (e.g. ./run.sh --editor)
set -euo pipefail
cd "$(dirname "$0")"

GODOT="${GODOT:-$(command -v godot || echo "$HOME/.local/bin/godot")}"
[ -x "$GODOT" ] || { echo "Godot not found. Set \$GODOT or install godot on PATH." >&2; exit 1; }

if [ "$(uname)" = "Linux" ] && [ "${GPU:-0}" != "1" ]; then
  export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
  echo "Rendering: software GL (llvmpipe). Use 'GPU=1 ./run.sh' to force the GPU."
fi

echo "Using $("$GODOT" --version 2>/dev/null | head -1)"
echo "Importing assets…"
if ! "$GODOT" --headless --path . --import; then
  echo "Import errored — rebuilding the .godot cache from scratch…"
  rm -rf .godot
  "$GODOT" --headless --path . --import
fi

exec "$GODOT" --path . "$@"
