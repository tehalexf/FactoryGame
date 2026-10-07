# DEEP FOUNDRY

A dieselpunk first-person factory-defense game. You build a production line,
and that production line *is* your weapon: belts feed turrets, crafted
components become modular gear, and the artillery silo only fires what your
factory managed to assemble beforehand.

Dig deeper for better ore and you wake worse things. Scale up production and
the Heat you generate brings the waves in faster. Every expansion is a bet.

**Status:** design settled, implementation not started.

## Setup

Once per clone, install the repo's git hooks. This repository is public and
purchased assets forbid redistribution, so a pre-commit licence guard is not
optional:

```sh
bash tools/git/install_hooks.sh
```

## Reading order

| Document | What it is |
|---|---|
| [GLOSSARY.md](GLOSSARY.md) | Domain glossary. The project's vocabulary. Start here. |
| [docs/DESIGN.md](docs/DESIGN.md) | The settled design and milestone plan. |
| [docs/ASSETS.md](docs/ASSETS.md) | Asset sources, licenses, and what must never be committed. |
| [docs/ASSET_PIPELINE.md](docs/ASSET_PIPELINE.md) | FBX-to-glTF conversion, the shared humanoid skeleton, and the licence guard. |
| [docs/adr/](docs/adr/) | Architecture decision records. |

## Stack

- **Engine:** Godot 4.6 — used as a renderer and input layer only.
- **Simulation:** custom, deterministic, fixed-point integer maths, living
  entirely outside the node tree. GDScript first, hot loops to C++ via
  GDExtension when profiling demands it.
- **Multiplayer:** 4-player deterministic lockstep, inputs-only on the wire.
- **Art:** AI-generated textures and 2D, Blender-scripted machines, CC0 and
  purchased rigged characters.

## Licence

Code is MIT. Art and audio are **not** uniformly licensed — see
[docs/ASSETS.md](docs/ASSETS.md) before reusing anything.
