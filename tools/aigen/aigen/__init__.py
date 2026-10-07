"""Local AI generation of the project's 2D art.

See ``tools/aigen/README.md``. The modules split along one line: everything
that can be reasoned about and tested without a GPU lives in `recipes`,
`tiling`, `framing` and `manifest`; `pipeline` is the thin plumbing that wires
a diffusion model to them.
"""
