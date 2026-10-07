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
/mnt/c/Windows/System32/cmd.exe /c start "" \
  "C:\\Users\\Alex\\godot\\Godot_v4.7.2-stable_win64.exe" \
  --path "C:\\Users\\Alex\\FactoryGame" --resolution 1600x900 >/dev/null 2>&1
echo "launched on Windows"
