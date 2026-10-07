#!/usr/bin/env bash
# Create the aigen venv on top of the system torch install.
#
# HARD RULE: the system torch (2.12.1+cu130, CUDA working, in system
# dist-packages) must not be touched. This script therefore:
#   * creates the venv with --system-site-packages so torch is inherited
#   * never installs torch / torchvision / nvidia-* wheels
#   * never passes --break-system-packages
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="${AIGEN_VENV:-$HERE/.venv}"

if [[ ! -d "$VENV" ]]; then
  echo "==> creating venv at $VENV (--system-site-packages)"
  python3 -m venv --system-site-packages "$VENV"
fi

echo "==> checking inherited torch"
"$VENV/bin/python" - <<'PY'
import sys
try:
    import torch
except ModuleNotFoundError:
    sys.exit("FATAL: no torch visible in the venv. Recreate it with "
             "--system-site-packages; do not pip install torch.")
print(f"    torch {torch.__version__}  cuda_available={torch.cuda.is_available()}")
if not torch.cuda.is_available():
    sys.exit("FATAL: torch sees no CUDA device. Refusing to continue rather "
             "than papering over it by reinstalling torch.")
print(f"    device: {torch.cuda.get_device_name(0)}")
PY

echo "==> installing generation stack (torch excluded)"
"$VENV/bin/pip" install --no-input --upgrade-strategy only-if-needed \
  -r "$HERE/requirements.txt"

echo "==> re-checking torch after install"
"$VENV/bin/python" -c "import torch; assert torch.cuda.is_available(); print('    torch', torch.__version__, 'cuda ok')"
python3 -c "import torch; assert torch.cuda.is_available(); print('    system torch', torch.__version__, 'cuda ok')"

echo
echo "Done. Generate with:"
echo "  tools/aigen/.venv/bin/python tools/aigen/generate.py"
