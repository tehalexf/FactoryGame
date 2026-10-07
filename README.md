# DEEP FOUNDRY

A dieselpunk first-person factory-defense game. You build a production line,
and that production line *is* your weapon: belts feed turrets, crafted
components become modular gear, and the artillery silo only fires what your
factory managed to assemble beforehand.

Dig deeper for better ore and you wake worse things. Scale up production and
the Heat you generate brings the waves in faster. Every expansion is a bet.

**Status:** Milestone 1 step 1. The deterministic simulation core and its test
harness exist; there is no gameplay and nothing is rendered yet.

## Running it

Run the test suite — this is the one-line CI command, and it exits non-zero on
failure:

```bash
tools/run_tests.sh
```

Run the game:

```bash
godot --path .
```

Both need Godot 4.7.2 on `PATH` as `godot`. See [CLAUDE.md](CLAUDE.md) for the
full toolchain, the project layout, and the conventions the code follows.

## Reading order

| Document | What it is |
|---|---|
| [GLOSSARY.md](GLOSSARY.md) | Domain glossary. The project's vocabulary. Start here. |
| [docs/DESIGN.md](docs/DESIGN.md) | The settled design and milestone plan. |
| [CLAUDE.md](CLAUDE.md) | How to build, run and test; code layout and conventions. |
| [docs/ASSETS.md](docs/ASSETS.md) | Asset sources, licenses, and what must never be committed. |
| [docs/adr/](docs/adr/) | Architecture decision records. |

## Stack

- **Engine:** Godot 4.7.2 — used as a renderer and input layer only.
- **Simulation:** custom, deterministic, fixed-point integer maths, living
  entirely outside the node tree. GDScript first, hot loops to C++ via
  GDExtension when profiling demands it.
- **Multiplayer:** 4-player deterministic lockstep, inputs-only on the wire.
- **Art:** AI-generated textures and 2D, Blender-scripted machines, CC0 and
  purchased rigged characters.

## Licence

Code is MIT. Art and audio are **not** uniformly licensed — see
[docs/ASSETS.md](docs/ASSETS.md) before reusing anything.
