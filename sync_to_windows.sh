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

/mnt/c/Windows/System32/cmd.exe /c start "" \
  "C:\\Users\\Alex\\godot\\Godot_v4.7.2-stable_win64.exe" \
  --path "C:\\Users\\Alex\\FactoryGame" --resolution 1600x900 >/dev/null 2>&1
echo "launched on Windows"
