# DEEP FOUNDRY — working notes

How to build, run and test this project, and the conventions the code follows.
Design lives in [docs/DESIGN.md](docs/DESIGN.md), vocabulary in
[GLOSSARY.md](GLOSSARY.md), architecture rationale in [docs/adr/](docs/adr/).

## Commands

```bash
tools/assets/run_tests.sh        # asset pipeline: licence guard, FBX conversion, Godot import
tools/run_tests.sh              # the whole suite, headless. This is the CI command.
tools/run_tests.sh determinism   # only tests whose case.method contains "determinism"
godot --path .                   # run the game
godot --headless --path . --quit-after 120   # launch headless for 120 frames
```

`tools/run_tests.sh` exits 0 when green and non-zero on any failure, load error,
or an unfiltered run that executed no tests. Set `GODOT=/path/to/godot` to use a
specific binary.

The asset-pipeline suite is separate because it drives Blender and Python rather
than the engine's test runner; see
[docs/ASSET_PIPELINE.md](docs/ASSET_PIPELINE.md). Run
`bash tools/git/install_hooks.sh` once per clone to install its licence guard as
a pre-commit hook — the repository is public and purchased assets must never be
committed.

`tools/run_tests.sh` runs `--import` first on every invocation. That is not optional: `class_name`
globals resolve through `.godot/global_script_class_cache.cfg`, which only an
import pass rebuilds, so a newly added class otherwise fails with a confusing
"Identifier not declared in the current scope".

## Toolchain

| Tool | Version | Notes |
|---|---|---|
| Godot | 4.7.2 stable | On `PATH` as `godot`. ADR 0001 originally said 4.6; amended. |
| scons | 4.11.1 | For GDExtension builds. Not needed yet. |
| Blender | 5.2.2 LTS | Art pipeline. glTF 2.0 ships; FBX is intake only. |

GDScript, not C#. C++ via GDExtension only when profiling demands it.

## Layout

```
sim/      the Simulation. Pure GDScript, no Godot node types, no floats.
game/     the Godot layer. Input producers and state readers only.
content/  Machine, Recipe and tuning definitions. Data, not code.
tests/    test runner, TestCase base, and tests/cases/ for the cases themselves.
assets/   committed CC0 and self-authored assets. intake/ holds the source FBX.
tools/    developer scripts. tools/assets/ is the asset pipeline and its tests.
docs/     design, ADRs, asset licensing.
```

The split between `sim/` and `game/` is the project's load-bearing boundary, and
it runs one way only: `game/` depends on `sim/`, never the reverse. Nothing in
`sim/` may reference `Node`, the scene tree, or any Godot type whose state is
float-based.

## The Simulation façade is the only seam

`sim/simulation.gd` exposes exactly three things:

```
step(actions)    advance exactly one tick
hash()           reduce the whole state to one integer
query_*(...)     read-only projections
```

Everything behind it — grid, Belts, Machines, Power, Heat, Waves, Turrets, Silo,
Delivery — is tested *through* those three, never directly. A test that reaches
into a module's internals breaks when the module is refactored and tells you
nothing about whether the game works. The one exception is leaf utility libraries
with contracts of their own — `Fixed`, `DeterministicRng`, `StateHasher`, and the
definition loaders `CsvTable`, `TomlDocument` and `Definitions` — which are tested
directly because their rounding, bit-level behaviour and error messages cannot be
observed any other way. "line 7 of recipes.csv names a rate that is not a number"
is not something `step`, `hash` or a query can tell you.

Queries return copies, never references into state. The Godot layer holds no
authoritative state whatsoever.

## Content definitions

Machines, Recipes and tuning values are **data**, in `content/`:

```
content/machines.csv    one row per Machine
content/recipes.csv     one row per Recipe
content/tuning.toml     balance numbers that are not per-Machine or per-Recipe
```

**Adding a Machine or a Recipe is a row. It is never a code change.** There is no
registry, no enum and no Item table — the set of Items is exactly the set the
Recipes mention, interned in sorted order. Every column is documented in the
header comment of the file it belongs to; read that before adding a row.

`content/.gdignore` is load-bearing. Without it Godot's importer claims every
`.csv` in the directory as a translation table, warns on each import, and strips
the rows from an export. These files are read with `FileAccess`, not `load()`.

`Definitions.load_from_directory` returns a set that either loaded or did not:

- Machines, Recipes and Items are **sorted by id**, and tuning keys are sorted
  too, so the index space is a function of the content and not of the order rows
  happen to be written in. Row order, comments and blank lines cannot reach the
  state hash.
- A malformed value is an **error naming the file, the row and the column**.
  There are no defaults anywhere: a typo'd rate does not become 0, a missing
  tuning key does not become 0, a Machine pointing at a Recipe that does not
  exist is not quietly Recipe-less.
- A set with any error at all carries **no definitions**. Half a definition set
  is more dangerous than none, because it looks usable.
- A tuning key nothing reads is a **warning**, because a file carrying a number
  that does nothing lies to whoever is tuning it.

`sim/csv_table.gd` and `sim/toml_document.gd` are the only parsers. Both are
hand-rolled: Godot ships no TOML parser, and vendoring one into a public repo is
out (`docs/ASSETS.md`). The TOML subset is sections, `key = value`, comments,
integers, decimals, quoted strings, `true`/`false` — and nothing else. Arrays,
inline tables and dates are valid TOML and are refused by name and line number.
If you need a fourth data file, reuse `CsvTable` rather than writing a parser.

Rates are written in decimal because that is how a human reasons about them, and
cross into fixed point exactly once, through `Fixed.from_decimal_string`, which
floors like every other lossy operation. No float exists at any point.

## Hot-reload

Editing a content file while the game runs applies the change when you save it.

`game/definition_watcher.gd` owns the filesystem and clock half — both are
forbidden inside `sim/`, which is why it lives in `game/` next to `TickPump`. It
detects change by **content digest**, not modification time, so two saves in the
same second are not mistaken for one. `Main` polls it and queues the result.

**The reload is an Input Action**, `InputAction.Kind.RELOAD_DEFINITIONS`, not a
method on the façade. It therefore goes through `step`, is ordered with every
other intent, lands in a recorded script, and replays exactly. The façade is
still three things.

What that buys, and what every later ticket may rely on:

- A reload **changes the state hash** at the tick it is applied. The definition
  digest and a reload generation counter are both hashed.
- A reload is **not undoable**. Reloading the original files does not restore the
  earlier hash, because the Run did change.
- A reload that **failed to load is refused** — so is one with no payload, and
  one whose declared digest disagrees with the set it carries. A refusal leaves
  the definitions and the generation counter untouched and the Run running. A
  typo mid-edit must never take a Run down.
- A `ReplayRecording` carries the **digest of the definitions it was made under**.
  `verify` compares that before it compares a single tick and reports
  `definitions_mismatch` — so a fixture cannot quietly pass against content that
  has since changed, and a content change is never misreported as a tick
  divergence. Leave `definitions` null in a fixture and the replay re-reads
  `content/`, which is what makes that check bite.

In co-op this is the Host's intent broadcast like any other, and the digest is
what lets a client whose own files hash differently refuse instead of desyncing.

## Determinism rules

From [ADR 0002](docs/adr/0002-deterministic-lockstep-inputs-only-networking.md).
Inside `sim/`, all four are absolute:

1. **Fixed-point integers only.** No floats in state or in intermediate steps.
   `Fixed.to_float` is the single sanctioned crossing and is outbound only.
2. **No wall-clock time.** The Simulation knows which tick it is on and nothing
   else. Deciding *when* to step belongs to `game/tick_pump.gd`.
3. **No unseeded randomness.** `DeterministicRng`, seeded at construction, is the
   only source. Never `randi()`, `randf()` or `RandomNumberGenerator`.
4. **No iteration over an unordered collection.** Arrays indexed by id, in index
   order. Sort keys first where a Dictionary is unavoidable.

`tests/cases/test_simulation_purity.gd` enforces all four mechanically against
every file in `sim/`. To take a sanctioned exception, put
`# purity-ok: <reason>` on the offending line. There are three in the whole
Simulation; the test fails if that count drifts far upward.

## Adding state to the Simulation

Feed it into `hash()`. State that is not hashed is state whose divergence the
determinism harness cannot see, which quietly weakens the guarantee the whole
architecture rests on.

## The determinism harness

`sim/determinism_harness.gd` records a script of Input Actions, replays it from an
identical starting state, and compares the state hash **tick by tick** — not just
at the end, because a fault that perturbs a few ticks and settles back is still a
desync.

Every subsequent ticket is expected to leave a replay fixture behind:

```gdscript
var script: InputScript = InputScript.new()
script.add_tick([InputAction.move(0, Fixed.ONE, 0)])
script.add_idle_ticks(30)

var recording: ReplayRecording = DeterminismHarness.record(script, seed, players)
var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
assert_true(divergence.is_identical, divergence.describe())
```

`record` takes an optional `Definitions`. Leave it out in a fixture: the replay
then re-reads `content/`, and a content change that would alter the Run is
reported as a `definitions_mismatch` rather than passing unnoticed. Pass one when
the scenario needs content the shipped files do not have.

`verify` takes an optional replacement Simulation, which is how a save/load round
trip gets proved exact and how the harness itself is proved to have teeth.

## Conventions

- Files and directories `snake_case.gd`; classes `PascalCase` via `class_name`.
- Tabs for indentation, as Godot's formatter expects.
- Static typing everywhere, including loop variables (`for i: int in ...`).
- Test files `tests/cases/test_*.gd` extending `TestCase`, methods `test_*`.
  Discovery and execution are sorted by name, so the suite is itself
  deterministic.
- Test names read as specifications — `test_a_turret_without_ammunition_does_not_fire`,
  not `test_turret_3`.
- Expected values in tests come from a worked example or a known literal, never
  from recomputing what the code does. `Fixed.mul(a, b) == (a * b) >> 16` asserts
  nothing.
- Domain vocabulary from `GLOSSARY.md`, capitalised: Nest, Breach, Factory,
  Machine, Belt, Heat, Wave, Turret, Silo, Charge, Delivery.
- Fixed-point constants are written `Fixed.from_rational(1, 3)`, never as a
  decimal literal. In a *data* file a rate is written in decimal and parsed with
  `Fixed.from_decimal_string`.
- **Every test method must assert something.** A GDScript runtime error — a call
  to a method that does not exist, an index out of range — aborts the method on
  the spot with nothing a test can catch, so the runner counts assertions and
  fails a method that made none. If a test's happy path returns early, assert
  explicitly rather than falling off the end.

## Test runner

Zero dependencies — no addons. The spec's first choice was gdUnit4; a
zero-dependency headless runner was its sanctioned fallback and is what shipped,
to avoid vendoring an addon into a public repository and to keep full control of
headless exit codes. There is no JUnit XML output yet; add it when CI needs it.
