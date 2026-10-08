#!/usr/bin/env bash
# Copies the project to the Windows side and relaunches it there.
#
# WSLg renders through llvmpipe and does not implement the Wayland pointer
# constraints a captured mouse needs, so the game is played from Windows where
# it gets the real GPU and a real mouse grab.
set -euo pipefail
cd "$(dirname "$0")"
rsync -a --delete \
  --exclude '.git' --exclude '.godot' --exclude '.claude' \
  --exclude 'assets_licensed' --exclude 'tools/aigen/.venv' \
  --exclude 'tools/aigen/models' --exclude 'tools/aigen/output' \
  ./ /mnt/c/Users/Alex/FactoryGame/

# The generated runtime assets, which the whole of assets_licensed/ is otherwise
# excluded from carrying. They are produced from purchased packs: never
# committed, but the running game needs them or the weapon in frame is a box,
# the yard is untextured stand-ins, and there is no sound at all.
#
#   tools/assets/convert_weapons.sh   tools/assets/convert_audio.sh
#   tools/assets/convert_props.sh
if [ -d assets_licensed/generated ]; then
  mkdir -p /mnt/c/Users/Alex/FactoryGame/assets_licensed/generated
  rsync -a --delete \
    assets_licensed/generated/ \
    /mnt/c/Users/Alex/FactoryGame/assets_licensed/generated/
  for kind in gear audio props; do
    count=$(ls "assets_licensed/generated/$kind" 2>/dev/null | wc -l)
    echo "  $kind: $count file(s)"
  done
else
  echo "generated assets: none — run the three tools/assets/convert_*.sh scripts"
fi
# Rebuild the Windows-side import cache before launching.
#
# Without this the game can come up as a grey screen: content/ gained required
# files (gear.csv, deliveries.csv, waves.csv) and assets gained meshes, and a
# stale .godot cache plus missing definitions means there is no world to draw.
# An import pass is also what rebuilds the class_name cache.
echo "importing on the Windows side..."
/mnt/c/Windows/System32/cmd.exe /c \
  "C:\\Users\\Alex\\godot\\Godot_v4.7.2-stable_win64_console.exe --headless --path C:\\Users\\Alex\\FactoryGame --import" \
  >/dev/null 2>&1 || true

# Launching is opt-in. Syncing used to launch too, which meant a window
# appeared whenever anything was copied across, including from automation.
if [ "${1:-}" = "--launch" ] || [ "${LAUNCH:-}" = "1" ]; then
  /mnt/c/Windows/System32/cmd.exe /c start "" \
    "C:\\Users\\Alex\\godot\\Godot_v4.7.2-stable_win64.exe" \
    --path "C:\\Users\\Alex\\FactoryGame" --resolution 1600x900 >/dev/null 2>&1
  echo "launched on Windows"
else
  echo "synced. run with --launch to start it, or launch it yourself from"
  echo "  C:\\Users\\Alex\\FactoryGame"
fi
